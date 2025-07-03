require 'dotenv'
require 'securerandom'
require 'yaml'

class Deploy
  DEPLOY_SERVER = ENV.fetch('DEPLOY_SERVER', nil)
  IMAGE_REPOSITORY_PREFIX = ENV.fetch('IMAGE_REPOSITORY_PREFIX', nil)
  SERVICE_DEFINITION_FILE = ENV.fetch('SERVICE_DEFINITION_FILE', nil)
  REQUIRED_ENVS = %w[HOSTNAME SERVICES].freeze
  SUPPORTED_TASKS = %w[prepare build deploy deploy_services deploy_service].freeze
  ENV_KEYS = %w[
    PROJECT_NAME
    POSTGRES_DB
    POSTGRES_USER
    POSTGRES_PASSWORD
    IMAGE
    RUBY_VERSION
    NODE_VERSION
    SECRET_KEY_BASE
    RAILS_MASTER_KEY
    HOSTNAME
  ]

  def initialize
    load_envs

    raise 'Missing required ENV variables!' unless DEPLOY_SERVER && IMAGE_REPOSITORY_PREFIX && SERVICE_DEFINITION_FILE
  end

  def prepare
    File.binwrite('.env', ENV_KEYS.map do |key|
      "#{key}=#{ENV[key]}"
    end.join("\n"))
    File.binwrite('docker-compose.yml', compose_file.to_yaml)
  end

  def build
    prepare

    system 'docker compose build --push web'
  end

  def deploy
    prepare

    system "ssh #{DEPLOY_SERVER} mkdir -p #{project_name}"
    system "scp .env docker-compose.yml #{DEPLOY_SERVER}:~/#{project_name}"
    system "ssh #{DEPLOY_SERVER} 'cd ~/#{project_name} && docker compose up -d --pull always'"
  end

  def deploy_services
    services.map do |service|
      deploy_service(service)
    end
  end

  def deploy_service(service = ARGV[1])
    return unless service

    filename = "#{service}.docker-compose.yml"
    File.binwrite(filename, service_compose_file(service).to_yaml.gsub('"', ''))

    system "ssh #{DEPLOY_SERVER} mkdir -p #{service}"
    system "scp #{filename} #{DEPLOY_SERVER}:~/#{service}"
    system "ssh #{DEPLOY_SERVER} 'cd ~/#{service} && docker compose -f #{filename} up -d'"
  end

  private

  def load_envs
    Dotenv.overwrite(Dir.pwd + '/.env', Dir.pwd + '/.env.production')

    set_envs

    REQUIRED_ENVS.each do |env|
      raise "ENV #{env} is empty!" if ENV[env].nil? || ENV[env].strip == ''
    end
  end

  def project_name
    ENV.fetch('PROJECT_NAME')
  end

  def ruby_version
    File.read('.ruby-version').strip
  end

  def node_version
    File.read('.nvmrc').strip
  end

  def set_envs
    ENV['PROJECT_NAME'] ||= project_name
    ENV['POSTGRES_DB'] ||= postgres_db
    ENV['POSTGRES_USER'] ||= postgres_user
    ENV['POSTGRES_PASSWORD'] ||= postgres_password
    ENV['IMAGE'] ||= image
    ENV['RUBY_VERSION'] ||= ruby_version
    ENV['NODE_VERSION'] ||= node_version
    ENV['SECRET_KEY_BASE'] ||= secret_key_base
    ENV['RAILS_MASTER_KEY'] ||= rails_master_key
  end

  def image
    "#{IMAGE_REPOSITORY_PREFIX}/#{project_name.sub('_', '-')}/web"
  end

  def postgres_db
    "#{project_name}_production"
  end

  def postgres_user
    "#{project_name}_user"
  end

  def postgres_password
    SecureRandom.hex(16)
  end

  def secret_key_base
    SecureRandom.hex(16)
  end

  def rails_master_key
    SecureRandom.hex(64)
  end

  def hostname
    ENV['HOSTNAME']
  end

  def service_definitions
    return {} unless File.exist?(SERVICE_DEFINITION_FILE)

    @service_definitions ||= YAML.load_file(SERVICE_DEFINITION_FILE)['services'] || {}
  end

  def services
    @services ||= (service_definitions.keys & ENV['SERVICES'].split(','))
  end

  def compose_file
    {
      'networks' => services.each_with_object({}) do |service, hash|
        hash[service] = { 'external' => true }
      end,

      'services' => {
        'web' =>
        {
          'image' => ENV['IMAGE'],
          'restart' => 'always',
          'build' => {

            'context' => '.',
            'args' => {
              'RUBY_VERSION' => ENV['RUBY_VERSION'],
              'NODE_VERSION' => ENV['NODE_VERSION']
            }
          },
          'env_file' => ['.env'],
          'environment' => {
            'EXECJS_RUNTIME' => 'Disabled'
          },
          'labels' => %W[
            traefik.enable=true
            traefik.http.middlewares.#{project_name}-redirectscheme.redirectscheme.permanent=true
            traefik.http.middlewares.#{project_name}-redirectscheme.redirectscheme.scheme=https
            traefik.http.routers.#{project_name}-http.entrypoints=web
            traefik.http.routers.#{project_name}-http.middlewares=#{project_name}-redirectscheme@docker
            traefik.http.routers.#{project_name}-http.rule=Host(`#{hostname}`)
            traefik.http.routers.#{project_name}-https.entrypoints=websecure
            traefik.http.routers.#{project_name}-https.rule=Host(`#{hostname}`)
            traefik.http.routers.#{project_name}-https.tls=true
            traefik.http.routers.#{project_name}-https.tls.certresolver=letsencrypt
            traefik.docker.network=proxy
          ],
          'networks' => services
        }
      }
    }
  end

  def service_compose_file(service) # rubocop:disable Metrics/MethodLength
    service_definition = service_definitions[service]

    {
      'networks' => { service => { 'external' => true } },
      'volumes' => { service => { 'external' => true } },
      'services' => {
        service => {
          **service_definition,
          'networks' => [service]
        }
      }
    }
  end
end
