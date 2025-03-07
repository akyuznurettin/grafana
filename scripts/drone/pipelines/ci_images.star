"""
This module contains steps and pipelines relating to creating CI Docker images.
"""

load(
    "scripts/drone/utils/utils.star",
    "pipeline",
)
load(
    "scripts/drone/vault.star",
    "from_secret",
    "gcp_download_build_container_assets_key",
)
load(
    "scripts/drone/utils/windows_images.star",
    "windows_images",
)
load(
    "scripts/drone/utils/images.star",
    "images",
)

def publish_ci_windows_test_image_pipeline():
    trigger = {
        "event": ["promote"],
        "target": ["ci-windows-test-image"],
    }
    pl = pipeline(
        name = "publish-ci-windows-test-image",
        trigger = trigger,
        edition = "",
        platform = "windows",
        steps = [
            {
                "name": "clone",
                "image": windows_images["wix_image"],
                "environment": {
                    "GITHUB_TOKEN": from_secret("github_token"),
                },
                "commands": [
                    'git clone "https://$$env:GITHUB_TOKEN@github.com/grafana/grafana-ci-sandbox.git" .',
                    "git checkout -f $$env:DRONE_COMMIT",
                ],
            },
            {
                "name": "build-and-publish",
                "image": windows_images["windows_server_core_image"],
                "environment": {
                    "DOCKER_USERNAME": from_secret("docker_username"),
                    "DOCKER_PASSWORD": from_secret("docker_password"),
                },
                "commands": [
                    "cd scripts\\build\\ci-windows-test",
                    "docker login -u $$env:DOCKER_USERNAME -p $$env:DOCKER_PASSWORD",
                    "docker build -t grafana/grafana-ci-windows-test:$$env:TAG .",
                    "docker push grafana/grafana-ci-windows-test:$$env:TAG",
                ],
                "volumes": [
                    {
                        "name": "docker",
                        "path": "//./pipe/docker_engine/",
                    },
                ],
            },
        ],
    )

    pl["clone"] = {
        "disable": True,
    }

    return [pl]

def publish_ci_build_container_image_pipeline():
    trigger = {
        "event": ["promote"],
        "target": ["ci-build-container-image"],
    }
    pl = pipeline(
        name = "publish-ci-build-container-image",
        trigger = trigger,
        edition = "",
        steps = [
            {
                "name": "validate-version",
                "image": images["alpine_image"],
                "commands": [
                    "if [ -z \"${BUILD_CONTAINER_VERSION}\" ]; then echo Missing BUILD_CONTAINER_VERSION; false; fi",
                ],
            },
            {
                "name": "download-macos-sdk",
                "image": images["cloudsdk_image"],
                "environment": {
                    "GCP_KEY": from_secret(gcp_download_build_container_assets_key),
                },
                "commands": [
                    "printenv GCP_KEY > /tmp/key.json",
                    "gcloud auth activate-service-account --key-file=/tmp/key.json",
                    "gsutil cp gs://grafana-private-downloads/MacOSX10.15.sdk.tar.xz ./scripts/build/ci-build/MacOSX10.15.sdk.tar.xz",
                ],
            },
            {
                "name": "build-and-publish",  # Consider splitting the build and the upload task.
                "image": images["cloudsdk_image"],
                "volumes": [{"name": "docker", "path": "/var/run/docker.sock"}],
                "environment": {
                    "DOCKER_USERNAME": from_secret("docker_username"),
                    "DOCKER_PASSWORD": from_secret("docker_password"),
                },
                "commands": [
                    "printenv DOCKER_PASSWORD | docker login -u \"$DOCKER_USERNAME\" --password-stdin",
                    "docker build -t \"grafana/build-container:${BUILD_CONTAINER_VERSION}\" ./scripts/build/ci-build",
                    "docker push \"grafana/build-container:${BUILD_CONTAINER_VERSION}\"",
                ],
            },
        ],
    )

    return [pl]
