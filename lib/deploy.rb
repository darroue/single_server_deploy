require 'dotenv'
require 'securerandom'
require 'yaml'

class Deploy
  DEPLOY_SERVER = ENV.fetch('DEPLOY_SERVER', nil)
  IMAGE_REPOSITORY_PREFIX = ENV.fetch('IMAGE_REPOSITORY_PREFIX', nil)
  SERVICE_DEFINITION_FILE = ENV.fetch('SERVICE_DEFINITION_FILE', nil)
  REQUIRED_ENVS = %w[HOSTNAME].freeze
  SUPPORTED_TASKS = %w[prepare build deploy deploy_services deploy_service].freeze

  def initialize
    raise 'Missing required ENV variables!' unless DEPLOY_SERVER && IMAGE_REPOSITORY_PREFIX && SERVICE_DEFINITION_FILE
  end

  def prepare
    @envs = Dotenv.parse('.env', '.env.production')

    set_envs

    (@envs.keys + REQUIRED_ENVS).each do |env|
      raise "ENV #{env} is empty!" unless @envs[env] != ''
    end

    File.binwrite('.env', @envs.map do |key, value|
      "#{key}=#{value}"
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

  def deploy_service(service = ARGV.first)
    return unless service

    File.binwrite('docker-compose.yml', service_compose_file(service).to_yaml)

    system "ssh #{DEPLOY_SERVER} mkdir -p #{service}"
    system "scp docker-compose.yml #{DEPLOY_SERVER}:~/#{service}"
    system "ssh #{DEPLOY_SERVER} 'cd ~/#{service} && docker compose up -d'"
  end

  private

  def project_name
    @project_name ||= File.basename(Dir.pwd)
  end

  def ruby_version
    File.read('.ruby-version').strip
  end

  def node_version
    File.read('.nvmrc').strip
  end

  def set_envs
    @envs['PROJECT_NAME'] ||= project_name
    @envs['POSTGRES_DB'] ||= postgres_db
    @envs['POSTGRES_USER'] ||= postgres_user
    @envs['POSTGRES_PASSWORD'] ||= postgres_password
    @envs['IMAGE'] ||= image
    @envs['RUBY_VERSION'] ||= ruby_version
    @envs['SECRET_KEY_BASE'] ||= secret_key_base
    @envs['RAILS_MASTER_KEY'] ||= rails_master_key
    @envs['EXECJS_RUNTIME'] ||= execjs_runtime
  end

  def execjs_runtime
    'Disabled'
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
    @envs['HOSTNAME']
  end

  def service_definitions
    return {} unless File.exist?(SERVICE_DEFINITION_FILE)

    @service_definitions ||= YAML.load_file(SERVICE_DEFINITION_FILE).try(:[], :services) || {}
  end

  def services
    @services ||= (service_definitions.keys & (@envs['SERVICES']&.split(',') || []))
  end

  def compose_file
    {
      'networks' => services.each_with_object({}) do |service, hash|
        hash[service] = { 'external' => true }
      end,

      'services' => {
        'web' =>
        {
          'image' => image,
          'restart' => 'always',
          'build' => {

            'context' => '.',
            'args' => {
              'RUBY_VERSION' => ruby_version,
              'NODE_VERSION' => node_version
            }
          },
          'env_file' => ['.env'],
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
            traefik.docker.network=web
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
          'networks' => [services]
        }
      }
    }
  end
end
