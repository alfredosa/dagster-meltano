# registry.gitlab.com/meltano/meltano:latest is also available in GitLab Registry
ARG MELTANO_IMAGE=meltano/meltano:latest
FROM $MELTANO_IMAGE

WORKDIR /project

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
         build-essential gcc python3-dev libpq-dev \
  && apt-get autoremove -yqq --purge \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install any additional requirements
COPY ./requirements.txt .
RUN pip install -r requirements.txt

# Copy over Meltano project directory
COPY . .
RUN meltano install

# Don't allow changes to containerized project files
ENV MELTANO_PROJECT_READONLY 1

# Expose default port used by `meltano ui`
EXPOSE 5000
EXPOSE 3000

ENTRYPOINT ["meltano"]
