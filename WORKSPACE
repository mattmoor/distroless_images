workspace(name = "distroless_images")

git_repository(
    name = "io_baze_rules_docker",
    remote = "https://github.com/mattmoor/rules_docker.git",
    commit = "294c06a0366ad32e4c36fd68c97e1da48338c8f4",
)
load(
    "@io_bazel_rules_docker//docker:docker.bzl",
    "docker_repositories", "docker_pull",
)
docker_repositories()

docker_pull(
   name = "py_base",
   registry = "gcr.io",
   repository = "distroless/python2.7",
)
