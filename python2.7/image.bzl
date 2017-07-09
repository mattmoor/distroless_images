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

load(
  "@io_bazel_rules_docker//docker:build.bzl",
  _build_attrs="attrs",
  _build_outputs="outputs",
  _build_implementation="implementation",
)

def _dep_layer_impl(ctx):
  """Appends a layer for a single dependencies runfiles."""

  return _build_implementation(
    ctx, files=list(ctx.attr.dep.default_runfiles.files))

_dep_layer = rule(
    attrs = _build_attrs + {
	# The base image on which to overlay the dependency layers.
        "base": attr.label(default = Label("@py_base//image")),
	# The dependency whose runfiles we're appending.
        "dep": attr.label(mandatory = True),

        # Override the defaults.
        "data_path": attr.string(default = "."),
        # We put the files from dependency layers into a
        # binary-agnostic path to increase the likelihood
        # of layer sharing across images, then we symlink
        # them into the appropriate place in the app layer.
        "directory": attr.string(default = "/app"),
    },
    executable = True,
    outputs = _build_outputs,
    implementation = _dep_layer_impl,
)

def _app_layer_impl(ctx):
  """Appends the app layer with all remaining runfiles."""

  # Compute the set of runfiles that have been made available
  # in our base image.
  available = set()
  for dep in ctx.attr.layers:
    available += [f.short_path for f in dep.default_runfiles.files]

  # The name of the binary target for which we are populating
  # this application layer.
  basename = ctx.attr.binary.label.name
  binary_name = "/app/" + basename

  # All of the files are included with paths relative to
  # this directory.
  # TODO(mattmoor): Might there be more path after the workspace?
  directory = binary_name + ".runfiles/" + ctx.workspace_name

  # Compute the set of remaining runfiles to include into the
  # application layer.
  files = [f for f in ctx.attr.binary.default_runfiles.files
           if f.short_path not in available]

  # For each of the runfiles we aren't including directly into
  # the application layer, link to their binary-agnostic
  # location from the runfiles path.
  symlinks = {
    # Bazel built binaries expect `python` on the path
    # TODO(mattmoor): upstream a fix into distroless.
    "/usr/bin/python": "/usr/bin/python2.7",
    binary_name: directory + "/" + basename
  } + {
    directory + "/" + input: "/app/" + input
    for input in available
  }

  return _build_implementation(
    ctx, files=files,
    # TODO(mattmoor): Switch to entrypoint so we can more easily
    # add arguments when the resulting image is `docker run ...`.
    # Per: https://docs.docker.com/engine/reference/builder/#entrypoint
    # we should use the "exec" (list) form of entrypoint.
    cmd=[binary_name],
    directory=directory, symlinks=symlinks)

_app_layer = rule(
    attrs = _build_attrs + {
        # The py_binary target for which we are synthesizing an image.
        "binary": attr.label(mandatory = True),
	# The full list of dependencies that have their own layers
        # factored into our base.
        "layers": attr.label_list(),
	# The base image on which to overlay the dependency layers.
        "base": attr.label(default = Label("@py_base//image")),

        # Override the defaults.
        "data_path": attr.string(default = "."),
        "workdir": attr.string(default = "/app"),
    },
    executable = True,
    outputs = _build_outputs,
    implementation = _app_layer_impl,
)

def py_image(name, deps, layers=[], **kwargs):
  """Constructs a Docker image wrapping a py_binary target.

  Args:
    **kwargs: See py_binary.
  """
  binary_name = name + ".binary"

  # TODO(mattmoor): Use par_binary instead, so that a single target
  # can be used for all three.
  native.py_binary(name=binary_name, deps=deps + layers, **kwargs)

  index = 0
  base = None # Makes us use ctx.attr.base
  for dep in layers:
    this_name = "%s.%d" % (name, index)
    _dep_layer(name=this_name, base=base, dep=dep)
    base = this_name
    index += 1

  _app_layer(name=name, base=base, binary=binary_name, layers=layers)

