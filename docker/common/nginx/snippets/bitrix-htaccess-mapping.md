# Bitrix .htaccess to Nginx Mapping

This document shows how Apache .htaccess rules are translated to Nginx configuration.

## 1. Options -Indexes

### Apache (.htaccess)
```apache
Options -Indexes
```

### Nginx (bitrix.conf)
```nginx
autoindex off;
```

**Purpose:** Disables directory listing when no index file is present.

---

## 2. ErrorDocument 404

### Apache (.htaccess)
```apache
ErrorDocument 404 /404.php
```

### Nginx (bitrix.conf)
```nginx
error_page 404 /404.php;
```

**Purpose:** Handles 404 errors through PHP script.

---

## 3. URL Rewrite (SEF URLs)

### Apache (.htaccess)
```apache
<IfModule mod_rewrite.c>
  Options +FollowSymLinks
  RewriteEngine On
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-l
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteCond %{REQUEST_FILENAME} !/bitrix/urlrewrite.php$
  RewriteRule ^(.*)$ /bitrix/urlrewrite.php [L]
  RewriteRule .* - [E=REMOTE_USER:%{HTTP:Authorization}]
</IfModule>
```

### Nginx (bitrix.conf)
```nginx
# SEO: Remove trailing /index.php
if ($request_uri ~* "^(.*/)index\.php$") {
    return 301 $1;
}

# Main handler
location / {
    try_files $uri $uri/ @bitrix;
}

# REST API endpoint (separate for rate-limiting)
location ^~ /rest/ {
    try_files $uri $uri/ @bitrix;
}

# Bitrix routing handler (routing_index.php for Bitrix 22.0+)
# For older versions, change to: $document_root/bitrix/urlrewrite.php
location @bitrix {
    set $php_upstream bitrix:9000;
    fastcgi_pass $php_upstream;
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME $document_root/bitrix/modules/main/include/routing_index.php;
    fastcgi_param SCRIPT_NAME /bitrix/modules/main/include/routing_index.php;
    fastcgi_param SERVER_NAME $host;

    # HTTP Authorization passthrough
    fastcgi_param REMOTE_USER $http_authorization;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;

    # HTTPS and proxy headers
    fastcgi_param HTTPS $https if_not_empty;
    fastcgi_param BX_CACHE_SSL $https if_not_empty;
}
```

**Purpose:**
- If file/directory exists, serve directly
- Otherwise, pass to routing_index.php (Bitrix 22.0+ new router with urlrewrite.php fallback)
- Pass HTTP Authorization for REST API
- BX_CACHE_SSL for composite cache over HTTPS

---

## 4. DirectoryIndex

### Apache (.htaccess)
```apache
<IfModule mod_dir.c>
  DirectoryIndex index.php index.html
</IfModule>
```

### Nginx (bitrix.conf)
```nginx
index index.php index.html;
```

**Purpose:** Defines index file lookup order.

---

## 5. Options -MultiViews

### Apache (.htaccess)
```apache
<IfModule mod_negotiation.c>
  Options -MultiViews
</IfModule>
```

### Nginx
Not required — Nginx does not support content negotiation by default.

---

## 6. Static File Caching

### Apache (.htaccess)
```apache
<IfModule mod_expires.c>
  ExpiresActive on
  ExpiresByType image/jpeg "access plus 3 day"
  ExpiresByType image/gif "access plus 3 day"
  ExpiresByType image/png "access plus 3 day"
  ExpiresByType text/css "access plus 3 day"
  ExpiresByType application/javascript "access plus 3 day"
</IfModule>
```

### Nginx (bitrix.conf)
```nginx
# Images
location ~* \.(jpg|jpeg|gif|png|webp|svg|ico)$ {
    expires 3d;
    add_header Cache-Control "public, immutable";
    access_log off;
    error_page 404 /404.php;
}

# CSS and JavaScript
location ~* \.(css|js)$ {
    expires 3d;
    add_header Cache-Control "public, immutable";
    access_log off;
    error_page 404 /404.php;
}

# Fonts (30 days)
location ~* \.(ttf|ttc|otf|eot|woff|woff2)$ {
    expires 30d;
}

# Media files (30 days)
location ~* \.(mp4|mp3|ogg|ogv|webm|flv|swf)$ {
    expires 30d;
}
```

**Purpose:** Browser caching for static files (3 days for images/CSS/JS, 30 days for fonts/media).

---

## 7. BX_CACHE_SSL (Composite cache over HTTPS)

### Apache (.htaccess / .settings.php)
```apache
RewriteRule .* - [E=BX_CACHE_SSL:%{HTTPS}]
```

### Nginx (bitrix.conf)
```nginx
# In @bitrix and \.php$ locations:
fastcgi_param BX_CACHE_SSL $https if_not_empty;
```

**Purpose:** Bitrix composite cache needs to know if the request is HTTPS to generate correct cache file paths. Without this, composite cache may serve HTTP content over HTTPS or vice versa.

---

## 8. PHP-FPM Status/Ping Protection

### Apache
Not applicable (handled by PHP-FPM config).

### Nginx (bitrix.conf)
```nginx
location ~ ^/(status|ping)$ {
    return 404;
    access_log off;
}
```

**Purpose:** Prevents information leak from PHP-FPM status/ping endpoints.

---

## 9. .phar File Blocking

### Apache
Not typically covered in .htaccess.

### Nginx (bitrix.conf)
```nginx
location ~ \.phar$ {
    deny all;
    access_log off;
}
```

**Purpose:** Prevents PHP archive exploitation via direct URL access.

---

## Additional Security Rules

### Block PHP execution in upload
```nginx
location ~* /upload/.*\.(php|php3|php4|php5|php6|php7|php8|phtml|pl|asp|aspx|cgi|dll|exe|shtm|shtml|fcg|fcgi|fpl|asmx|pht|py|psp|rb|var)$ {
    types {
        text/plain text/plain php php3 php4 php5 php6 php7 php8 phtml pl asp aspx cgi dll exe ico shtm shtml fcg fcgi fpl asmx pht py psp rb var;
    }
}
```

### Block system directories (using ^~ for priority over regex)
```nginx
location ^~ /bitrix/modules { deny all; }
location ^~ /bitrix/local_cache { deny all; }
location ^~ /bitrix/stack_cache { deny all; }
location ^~ /bitrix/managed_cache { deny all; }
location ^~ /bitrix/php_interface { deny all; }
```

### Block /bitrix/cache/ (except CSS/JS)
```nginx
# CSS/JS exception (MUST be declared before the deny rule)
location ~* ^/bitrix/cache/(css/.+\.css|js/.+\.js)$ {
    expires 30d;
}

# Block everything else in /bitrix/cache/
location ~* ^/bitrix/cache/ {
    deny all;
}
```

### Block VCS and hidden files
```nginx
location ~* /\.ht { deny all; }
location ~* /\.(svn|hg|git) { deny all; }
```

### Block composite cache config
```nginx
location ~* ^/bitrix/html_pages/\.config\.php { deny all; }
location ~* ^/bitrix/html_pages/\.enabled { deny all; }
```

---

## Push & Pull (WebSocket support)

### Apache
Requires mod_proxy_wstunnel — often not available.

### Nginx (bitrix.conf)
```nginx
location /bitrix/sub/ {
    proxy_pass http://push-sub:8010;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400s;
}

location /bitrix/subws/ {
    # Same as above — WebSocket endpoint
}

location /bitrix/pub/ {
    proxy_pass http://push-pub:9010;
    # Internal only — restricted to Docker network
}
```

**Purpose:** Real-time notifications via Push&Pull module.

---

## Testing

After applying configuration, verify:

```bash
# 1. Check nginx syntax
docker compose exec nginx nginx -t

# 2. Reload nginx
docker compose exec nginx nginx -s reload

# 3. Test SEF URLs (should return 200)
curl -I http://your-site.local/some-page/

# 4. Test 404 handling
curl -I http://your-site.local/nonexistent-page

# 5. Test static file caching (should have Cache-Control header)
curl -I http://your-site.local/images/logo.png

# 6. Test security (should return 403)
curl -I http://your-site.local/bitrix/modules/
curl -I http://your-site.local/upload/test.php
curl -I http://your-site.local/bitrix/cache/

# 7. Test REST API routing
curl -I http://your-site.local/rest/

# 8. Test index.php redirect (should 301 to /)
curl -I http://your-site.local/index.php

# 9. Test .phar blocking (should return 403)
curl -I http://your-site.local/test.phar

# 10. Test PHP-FPM status protection (should return 404)
curl -I http://your-site.local/status
```

---

## References

- [Nginx official documentation](https://nginx.org/en/docs/)
- [Bitrix Framework - Server setup](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=2483)
- [Bitrix Virtual Appliance](https://www.1c-bitrix.ru/products/virtual_appliance/)
