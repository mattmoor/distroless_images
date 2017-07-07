# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""A rule for creating a Python Docker image.

The signature of this rule is compatible with py_binary.
"""

# Perform a counting sort of the dependencies.
def _sort_by_runfiles_length(deps):
  count_to_deps = {}
  for dep in deps:
    count = len(dep.default_runfiles.files)
    entries = count_to_deps.get(count, [])
    entries += [dep]
    count_to_deps[count] = entries

  ordered_deps = []
  for count in sorted(count_to_deps.keys()):
    ordered_deps += count_to_deps[count]
  return ordered_deps

load(
  "@io_bazel_rules_docker//docker:build.bzl",
  _build_attrs="attrs",
  _build_outputs="outputs",
  _build_implementation="implementation",
)

def _impl(ctx):
  """Core implementation of py_image."""

  # We order the deps in increasing order of runfiles to
  # put supersets last.
  ordered_deps = _sort_by_runfiles_length(
    ctx.attr.deps + [ctx.attr.binary])

  seen = set()
  files = []
  for dep in ordered_deps:
    unique_files = set()
    for input in list(dep.default_runfiles.files):
      if input.path in seen:
        continue
      seen += [input.path]
      unique_files += [input]

    if ctx.attr.dep and dep == ctx.attr.dep:
      files = list(unique_files)

  # TODO(mattmoor): Instead of using "deps" implicitly in this way,
  # consider exposing a separate "layers" kwarg to augments "deps",
  # but indicate the layering specializing.  These layers should
  # include the transitive dependencies despite overlap with other
  # layers. We should order this kwarg in the reverse of what we do
  # above and elide layers that are fully covered.

  # We put the files from dependency layers into a binary-agnostic
  # path to increase the likelihood of layer sharing across images,
  # then we symlink them into the appropriate place in the app layer.
  dir = "/app"
  cmd = []
  symlinks = {}
  if ctx.attr.binary == ctx.attr.dep:
    name = ctx.attr.binary.label.name
    binary_name = "/app/" + name

    # TODO(mattmoor): Switch to entrypoint so we can more easily
    # add arguments when the resulting image is `docker run ...`.
    # Per: https://docs.docker.com/engine/reference/builder/#entrypoint
    # we should use the "exec" (list) form of entrypoint.
    cmd = [binary_name]
    dir = dir + "/" + name + ".runfiles/" + ctx.workspace_name
    symlinks = {
      # Bazel build binaries expect `python` on the path
      # TODO(mattmoor): upstream a fix into distroless.
      "/usr/bin/python": "/usr/bin/python2.7",
      binary_name: dir + "/" + name
    }
    for input in list(ctx.attr.binary.default_runfiles.files):
      if input in files:
        continue
      symlinks[dir + "/" + input.short_path] = "/app/" + input.short_path

  return _build_implementation(ctx, files=files, cmd=cmd,
                               directory=dir, symlinks=symlinks)

_py_image = rule(
    attrs = _build_attrs + {
        # The py_binary target for which we are synthesizing an image.
        "binary": attr.label(mandatory = True),
	# The individual "dep" of the image whose runfiles belong in
	# their own layer.
        "dep": attr.label(),
	# The full list of dependencies.
        "deps": attr.label_list(),
	# The base image on which to overlay the dependency layers.
        "base": attr.label(default = Label("@py_base//image")),

        # Override the defaults.
        "data_path": attr.string(default = "."),
        "workdir": attr.string(default = "/app"),
    },
    executable = True,
    outputs = _build_outputs,
    implementation = _impl,
)

def py_image(name, deps, **kwargs):
  """Constructs a Docker image wrapping a py_binary target.

  Args:
    **kwargs: See py_binary.
  """
  binary_name = name + ".binary"

  # TODO(mattmoor): Use par_binary instead, so that a single target
  # can be used for all three.
  native.py_binary(name=binary_name, deps=deps, **kwargs)

  index = 0
  base = None # use ctx.attr.base
  for x in deps:
    this_name = "%s.%d" % (name, index)
    _py_image(name=this_name, base=base, binary=binary_name, deps=deps, dep=x)
    base = this_name
    index += 1

  _py_image(name=name, base=base, binary=binary_name, deps=deps, dep=binary_name)

