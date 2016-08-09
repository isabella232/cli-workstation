#!/bin/bash -eux

pushd /tmp
  mkdir -p bosh-lite-deployment

  # assumes a bosh-lite has already been spun up
  bosh target 192.168.50.4

  # upload stemcell
  bosh upload stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent

  # upload etcd release
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/etcd-release

  # upload garden runc release
  nosh upload release https://bosh.io/d/github.com/cloudfoundry/garden-runc-release

  # upload cflinuxfs2
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cflinuxfs2-rootfs-release

  # create, upload & deploy cf-release
  pushd $HOME/workspace/cf-release
    git pull -r
    git checkout v$(git tag | cut -d v -f 2 | sort -g | tail -n 1)
    scripts/update
    bosh create release --force
    bosh upload release

    scripts/generate-bosh-lite-dev-manifest \
      ~/workspace/diego-release/manifest-generation/stubs-for-cf-release/enable_diego_windows_in_cc.yml
    bosh -n deploy
  popd

  # create, upload & deploy diego-release
  pushd $HOME/workspace/diego-release
    git pull -r
    git checkout $(g tag | tail -n 1)
    scripts/update
    bosh create release --force
    bosh upload release

    scripts/generate-bosh-lite-manifests
    bosh deployment bosh-lite/deployments/diego.yml
    bosh -n deploy
  popd

  # create, upload & deploy routing-release
  pushd $HOME/workspace/cf-routing-release
    git pull -r
    routing_version=$(g tag | tail -n 1)
    git checkout $routing_version
    scripts/update
    bosh -n upload release releases/routing-${routing_version}.yml
    scripts/generate-bosh-lite-manifest
		bosh -n deploy
  popd

	# redeploy cf to use diego and the routing release
	cat << EOF > property-overrides.yml
properties:
  cc:
    default_to_diego_backend: true
  routing_api:
    enabled: true
EOF

	pushd $HOME/cf-release
		scripts/generate-bosh-lite-dev-manifest $HOME/workspace/property-overrides.yml
		bosh -n deploy
  popd

  # adds the route for the bosh-lite
  $HOME/workspace/bosh-lite/bin/add-route
popd