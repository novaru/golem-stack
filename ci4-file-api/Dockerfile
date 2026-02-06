FROM php:8.3-fpm-alpine

# Install dependencies (all at once to use Alpine repos)
RUN apk add --no-cache \
    nginx \
    postgresql-dev \
    bash \
    icu-dev \
    && docker-php-ext-install pdo pdo_pgsql pgsql intl

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . /var/www/html/

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader

# Set permissions
RUN chown -R www-data:www-data /var/www/html/writable \
    && chmod -R 755 /var/www/html/writable \
    && mkdir -p /var/www/html/writable/uploads \
    && chown -R www-data:www-data /var/www/html/writable/uploads

# Nginx configuration
RUN rm /etc/nginx/http.d/default.conf
COPY <<'EOF' /etc/nginx/http.d/default.conf
server {
    listen 3000;
    server_name _;
    root /var/www/html/public;
    index index.php;

    client_max_body_size 100M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# PHP-FPM configuration
RUN echo "php_admin_value[post_max_size] = 100M" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "php_admin_value[upload_max_filesize] = 100M" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "php_admin_value[memory_limit] = 256M" >> /usr/local/etc/php-fpm.d/www.conf

# Start script
RUN cat > /start.sh <<'STARTSCRIPT'
#!/bin/bash
# Start PHP-FPM
php-fpm -D
# Start Nginx in foreground
nginx -g 'daemon off;'
STARTSCRIPT

RUN chmod +x /start.sh

# Expose port
EXPOSE 3000

# Health check (TCP check to avoid curl dependency)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD timeout 1 sh -c '</dev/tcp/127.0.0.1/3000' || exit 1

CMD ["/start.sh"]
