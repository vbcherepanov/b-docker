# Сопоставление .htaccess и Nginx для Bitrix

Этот документ показывает, как правила из `.htaccess` переведены в конфигурацию Nginx.

## 1. Options -Indexes

### Apache (.htaccess)
```apache
Options -Indexes
```

### Nginx (bitrix.conf)
```nginx
autoindex off;
```

**Назначение:** Запрещает отображение списка файлов в директории, если нет индексного файла.

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

**Назначение:** Обработка 404 ошибок через PHP скрипт.

---

## 3. URL Rewrite (ЧПУ)

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
# Основная обработка
location / {
    try_files $uri $uri/ @bitrix;
}

# Обработчик ЧПУ
location @bitrix {
    set $php_upstream bitrix:9000;
    fastcgi_pass $php_upstream;
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME $document_root/bitrix/urlrewrite.php;
    fastcgi_param SCRIPT_NAME /bitrix/urlrewrite.php;
    fastcgi_param SERVER_NAME $host;

    # HTTP Authorization
    fastcgi_param REMOTE_USER $http_authorization;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
}
```

**Назначение:**
- Если файл/директория существует - отдать напрямую
- Иначе - передать в `/bitrix/urlrewrite.php` для обработки ЧПУ
- Передача HTTP Authorization для REST API

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

**Назначение:** Определяет порядок индексных файлов.

---

## 5. Options -MultiViews

### Apache (.htaccess)
```apache
<IfModule mod_negotiation.c>
  Options -MultiViews
</IfModule>
```

### Nginx
Не требуется - Nginx не поддерживает content negotiation по умолчанию.

---

## 6. Кеширование статических файлов

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
# Изображения
location ~* \.(jpg|jpeg|gif|png|webp|svg|ico)$ {
    expires 3d;
    add_header Cache-Control "public, immutable";
    access_log off;
    error_page 404 /404.html;
}

# CSS и JavaScript
location ~* \.(css|js)$ {
    expires 3d;
    add_header Cache-Control "public, immutable";
    access_log off;
    error_page 404 /404.html;
}
```

**Назначение:** Браузерное кеширование статических файлов на 3 дня.

---

## Дополнительные правила безопасности (не в .htaccess, но необходимы)

### Запрет выполнения PHP в upload
```nginx
location ~* /upload/.*\.(php|php3|php4|php5|php6|php7|php8|phtml|pl|asp|aspx|cgi|dll|exe|shtm|shtml|fcg|fcgi|fpl|asmx|pht|py|psp|rb|var)$ {
    types {
        text/plain text/plain php php3 php4 php5 php6 php7 php8 phtml pl asp aspx cgi dll exe ico shtm shtml fcg fcgi fpl asmx pht py psp rb var;
    }
}
```

### Запрет доступа к системным директориям
```nginx
location ~* ^/bitrix/(modules|local_cache|stack_cache|managed_cache|php_interface) {
    deny all;
    access_log off;
}

location ~* ^/bitrix/cache {
    deny all;
    access_log off;
}
```

### Запрет доступа к VCS и скрытым файлам
```nginx
location ~* /\.ht {
    deny all;
}

location ~* /\.(svn|hg|git) {
    deny all;
}
```

---

## Преимущества Nginx конфигурации

1. **Производительность:** Nginx обрабатывает статику быстрее Apache
2. **Безопасность:** Дополнительные правила защиты системных директорий
3. **Кеширование:** Более гибкие настройки с `Cache-Control`
4. **Прозрачность:** Явные правила вместо условных директив
5. **Композитный кеш:** Поддержка Bitrix Composite из коробки

---

## Тестирование

После применения конфигурации проверьте:

```bash
# 1. Проверка синтаксиса nginx
docker exec bitrix.local_nginx nginx -t

# 2. Перезагрузка nginx
docker exec bitrix.local_nginx nginx -s reload

# 3. Проверка ЧПУ
curl -I http://bitrix.local/some-page/

# 4. Проверка 404
curl -I http://bitrix.local/nonexistent

# 5. Проверка кеширования
curl -I http://bitrix.local/images/logo.png

# 6. Проверка безопасности (должен быть 403)
curl -I http://bitrix.local/bitrix/modules/
curl -I http://bitrix.local/upload/test.php
```

---

## Дополнительная информация

- [Официальная документация Nginx](https://nginx.org/ru/docs/)
- [Bitrix Framework - Настройка сервера](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=2483)
- [Bitrix Virtual Appliance](https://www.1c-bitrix.ru/products/virtual_appliance/)
