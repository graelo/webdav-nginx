# Rootless Multi-User WebDAV Sync Store Container

## Build the image

```sh
buildah unshare -- bash -c './build-container-webdav.sh 2>&1 | tee build_log.txt'
```

You can optionally embed your `webdav.conf`: corresponding lines are commented
out in the config, but I prefer mounting my config when running the container.

## Configuration

The nginx process is run by www-data, which is modified to be UID/GID=1000.

- Bind-mount sync store data in `/media/data`
- For multi-users setup, credentials for each user should be htpasswd files in
  a folder, and bind-mount that folder in `/etc/nginx/htpasswords/`
- Finally, bind-mount the following `webdav.conf` (adjusted to your needs!)
  into `/etc/nginx/conf.d/default.conf`

## Run the image

Extract from a Systemd Unit:

```systemd
ExecStart=/usr/bin/podman container run \
  --conmon-pidfile=%t/%N.pid \
  --cidfile=%t/%N.ctr-id \
  --cgroups=no-conmon \
  --userns=keep-id \
  --sdnotify=conmon \
  --replace \
  --rm \
  --detach \
  --volume=/etc/localtime:/etc/localtime:ro \
  --volume=/tank/containers/webdav/config/htpasswords:/etc/nginx/htpasswords:Z,U \
  --volume=/tank/containers/webdav/config/webdav.conf:/etc/nginx/conf.d/default.conf:Z,U \
  --volume=/tank/containers/webdav/data:/media/data:Z,U \
  --dns=your-host-ip \
  --publish=127.0.0.1:9008:8080 \
  --label="io.containers.autoupdate=registry" \
  --name=webdav \
  docker.io/graelo/webdav-nginx:rootless
```

## Example files for DevonThink and OmniFocus

I'm providing the example config for Omni products, because it is not trivial.

Example `webdav.conf`

```nginx
server {
    listen 8080;

    access_log /dev/stdout;
    error_log /dev/stdout info;

    client_max_body_size 0;

    location /devonthink {
        alias /media/data/devonthink;

        create_full_put_path on;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        charset utf-8;

        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS;
        dav_access user:rw group:rw all:r;

        auth_basic "Restricted DevonThink";
        auth_basic_user_file /etc/nginx/htpasswords/devonthink.htpasswd;
    }

    location /omnifocus {
        alias /media/data/omnifocus;

        create_full_put_path on;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        charset utf-8;

        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS;
        dav_access user:rw group:rw all:r;

        auth_basic "Restricted OmniFocus";
        auth_basic_user_file /etc/nginx/htpasswords/omnifocus.htpasswd;
    }
}
```

Here's the corresponding nginx reverse proxy:

```nginx
server {
  server_name webdav.graelo.cc;
  listen 80;

  location / {
    return 301 https://$host$request_uri;
  }

  access_log /var/log/nginx/webdav.graelo.cc-access.log;
  error_log /var/log/nginx/webdav.graelo.cc-error.log;
}

server {
  server_name webdav.graelo.cc;
  listen 443 ssl;

  ssl_certificate   /etc/ssl/localcerts/webdav.graelo.cc/chained.crt;
  ssl_certificate_key /etc/ssl/localcerts/webdav.graelo.cc/service.key;

  add_header    Strict-Transport-Security "max-age=31536000" always;
  add_header    X-Frame-Options SAMEORIGIN;
  add_header    X-Content-Type-Options nosniff;

  client_max_body_size 0;

  location /devonthink {
    set $target http://127.0.0.1:9005;

    proxy_pass $target;

    proxy_buffering off;

    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-User $remote_user;

    # Add these lines for authentication handling
    proxy_set_header Authorization $http_authorization;
    proxy_pass_header Authorization;

    # WebDAV specific settings
    proxy_set_header Destination $http_destination;
    proxy_set_header Overwrite $http_overwrite;

    # Optional: enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
  }

  location /omnifocus {
    set $target http://127.0.0.1:9005;

    set $fixed_destination $http_destination;
    set $destination_check "";

    # Remove the scheme and host from the Destination header
    if ($http_destination ~ ^https?://[^/]+(.*)$) {
      set $fixed_destination $1;
    }

    # Check if request_uri ends with a slash
    if ($request_uri ~ ^.+/$) {
      set $destination_check "${destination_check}A";
    }

    # Check if fixed_destination ends with a slash
    if ($fixed_destination ~ ^.+/$) {
      set $destination_check "${destination_check}B";
    }

    # Adjust fixed_destination based on checks
    if ($destination_check = "A") {
      set $fixed_destination "${fixed_destination}/";
    }
    if ($destination_check = "B") {
      set $fixed_destination "${fixed_destination}";
    }
    if ($destination_check = "") {
      set $fixed_destination "${fixed_destination}";
    }
    if ($destination_check = "AB") {
      set $fixed_destination "${fixed_destination}";
    }

    proxy_pass $target;

    proxy_buffering off;

    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-User $remote_user;

    # Add these lines for authentication handling
    proxy_set_header Authorization $http_authorization;
    proxy_pass_header Authorization;

    # WebDAV specific settings
    proxy_set_header Destination $fixed_destination;
    proxy_set_header Overwrite $http_overwrite;

    # Optional: enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
  }

  access_log /var/log/nginx/webdav.graelo.cc-access.log;
  error_log /var/log/nginx/webdav.graelo.cc-error.log;
}
```
