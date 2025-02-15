#!/bin/bash

set -eo pipefail

# Pull the base image
ctr_id=$(buildah from docker.io/debian:bookworm-slim)

# Set labels
buildah config --label maintainer="graelo <containers@graelo.cc>" "$ctr_id"

# Update and upgrade packages, install additional packages
buildah run "$ctr_id" sh -c "
    apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y nginx nginx-extras apache2-utils \
    && usermod -u 1000 www-data \
    && groupmod -g 1000 www-data \
    "

mount_point=$(buildah mount "$ctr_id")
# sed -i 's/worker_processes auto;/worker_processes 4;/' "$mount_point/etc/nginx/nginx.conf"
# sed -i '/^user/d' "$mount_point/etc/nginx/nginx.conf"
sed -i -e 's/worker_processes auto;/worker_processes 4;/' -e '/^user/d' "$mount_point/etc/nginx/nginx.conf"
buildah unmount "$ctr_id"

# Copy custom webdav.conf file
# buildah copy "$ctr_id" ./webdav.conf /etc/nginx/conf.d/default.conf

# Remove default sites-enabled files
buildah run "$ctr_id" sh -c "rm /etc/nginx/sites-enabled/*"

# Create and set ownership for the data directory
buildah run "$ctr_id" sh -c "mkdir -p /media/data && chown -R www-data:www-data /media/data"
buildah run "$ctr_id" sh -c "chown -R www-data:www-data /var/log/nginx /var/lib/nginx /var/run/ /etc/nginx /usr/share/nginx"

buildah config --user www-data "$ctr_id"

# Set the default command
buildah config --cmd '["nginx", "-g", "daemon off;"]' "$ctr_id"

# Set the entrypoint
# buildah copy "$ctr_id" ./entrypoint.sh /
# buildah run "$ctr_id" chmod +x /entrypoint.sh
# buildah config --entrypoint '["/entrypoint.sh"]' "$ctr_id"

# Run the entrypoint script and start nginx
buildah commit "$ctr_id" docker.io/graelo/webdav-nginx:rootless
