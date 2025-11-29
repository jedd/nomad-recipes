# Recoll WebUI Docker Image
# Based on medoc92's maintained fork: https://framagit.org/medoc92/recollwebui

# Using Debian base instead of python image so system packages work correctly
# This means it takes a bit longer to build, but is a bit less recalcitrant.

# I'm usually happy with latest Debian base image.
FROM debian:trixie

LABEL maintainer="dockerbuilder@jeddi.org"
LABEL description="Recoll full-text search with web interface"

# Install Recoll and required dependencies
# Note: pstotext is obsolete since perhaps bookworm, so we use pdftotext from poppler-utils.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    recoll \
    antiword \
    poppler-utils \
    unrtf \
    untex \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for the webui:
#   python3-recoll provides the Python bindings for Recoll
#   python3-waitress provides the WSGI server
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-recoll python3-waitress && \
    rm -rf /var/lib/apt/lists/*

# Clone the recollwebui repository - this was valid as of 2025-11
#   https://framagit.org/medoc92/recollwebui/
# with the most recent update 3 days earlier.
WORKDIR /opt
RUN git clone https://framagit.org/medoc92/recollwebui.git recoll-webui

WORKDIR /opt/recoll-webui

# Create directories for Recoll configuration and index
RUN mkdir -p /root/.recoll /documents

# Expose the default webui port
EXPOSE 8080

# Run the standalone webui server
# -a 0.0.0.0 binds to all interfaces (required for Docker)
# -p 8080 listens on port 8080
CMD ["python3", "webui-standalone.py", "-a", "0.0.0.0", "-p", "8080"]

