FROM postgres:17-alpine

# Install system dependencies (including su-exec for dropping privileges)
RUN apk add --no-cache python3 py3-pip python3-dev gcc musl-dev gettext su-exec

# Install Patroni and its Python dependencies
RUN pip3 install --no-cache-dir --break-system-packages psycopg2-binary 'patroni[etcd3]'

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Make entrypoint script executable
RUN chmod +x /entrypoint.sh

# Create the data directory and set ownership
RUN mkdir -p /var/lib/postgresql/data && chown -R postgres:postgres /var/lib/postgresql/data

# Expose PostgreSQL and Patroni API ports
EXPOSE 5432 8008

# Run as root initially (entrypoint will drop to postgres)
# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
