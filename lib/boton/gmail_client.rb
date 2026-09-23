# frozen_string_literal: true

require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'socket'
require 'uri'

module Boton
  class GmailClient
    SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_READONLY
    LOOPBACK_HOST = '127.0.0.1'
    AUTH_TIMEOUT = 300
    APPLICATION_NAME = 'Macro Transaction Parser'
    DEFAULT_CREDENTIALS_PATH = File.expand_path('../../config/credentials.json', __dir__)
    DEFAULT_TOKEN_PATH = File.expand_path('../../config/token.yaml', __dir__)
    CREDENTIALS_PATH = ENV.fetch('BOTON_CREDENTIALS', DEFAULT_CREDENTIALS_PATH)
    TOKEN_PATH = ENV.fetch('BOTON_TOKEN', DEFAULT_TOKEN_PATH)
    REVERSAL_SUBJECT = 'Aviso de reverso de compra'

    def initialize(logger: nil)
      @logger = logger
      @service = authorize
    end

    # Autoriza la aplicación con Gmail API usando OAuth2
    # Primera vez: flujo interactivo (abre navegador)
    # Siguientes: usa token guardado en config/token.yaml
    def authorize
      # Verificar que existe credentials.json
      unless File.exist?(CREDENTIALS_PATH)
        error_msg = "No se encontró #{CREDENTIALS_PATH}"
        log(:fatal, error_msg)
        log(:fatal, 'Por favor seguir instrucciones en README.md para configurar Google Cloud')
        raise error_msg
      end

      # Configurar autorización
      client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
      token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
      authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)

      user_id = 'default'
      credentials = authorizer.get_credentials(user_id)

      # Si no hay credenciales o están expiradas, hacer flujo de autorización
      if credentials.nil?
        credentials = authorize_with_loopback(authorizer, user_id)
        log(:info, "Autorización exitosa. Token guardado en #{TOKEN_PATH}")
      else
        log(:info, 'Usando token existente')
      end

      # Crear servicio de Gmail
      service = Google::Apis::GmailV1::GmailService.new
      service.client_options.application_name = APPLICATION_NAME
      service.authorization = credentials

      service
    rescue Google::Apis::AuthorizationError => e
      log(:error, "Error de autorización: #{e.message}")
      log(:warn, "El token puede estar expirado. Intenta borrar #{TOKEN_PATH} y volver a ejecutar")
      raise
    rescue SocketError => e
      log(:fatal, "Error de conexión: #{e.message}")
      log(:fatal, 'Verificar conexión a internet')
      raise
    end

    # Busca emails de transacciones para una fecha específica
    # Retorna array de mensajes con {id, message_id}
    def fetch_transactions(date)
      query = build_query(date)
      log(:info, "Buscando emails para fecha: #{date}")
      log(:debug, "Query: #{query}") if @logger

      messages = list_all_messages(query)

      log(:info, "Encontrados #{messages.size} emails")
      messages
    rescue Google::Apis::Error => e
      log(:error, "Error al buscar emails: #{e.message}")
      raise
    end

    # Busca emails de reverso de compra para una fecha específica
    # Retorna array de mensajes con {id, message_id}
    def fetch_reversals(date)
      query = build_query(date, subject: REVERSAL_SUBJECT)
      log(:info, "Buscando reversos para fecha: #{date}")
      log(:debug, "Query: #{query}") if @logger

      messages = list_all_messages(query)

      log(:info, "Encontrados #{messages.size} reversos")
      messages
    rescue Google::Apis::Error => e
      log(:error, "Error al buscar reversos: #{e.message}")
      raise
    end

    # Obtiene el contenido HTML de un mensaje específico
    # Retorna string con HTML o nil si no se encuentra
    def get_message_content(message_id)
      log(:debug, "Obteniendo contenido del mensaje: #{message_id}")

      message = @service.get_user_message('me', message_id, format: 'full')

      log(:debug, "Mensaje obtenido: payload.mime_type=#{message.payload.mime_type}")
      log(:debug, "Payload tiene parts? #{!message.payload.parts.nil?}")
      log(:debug, "Número de parts: #{message.payload.parts&.size || 0}")

      html = extract_html_body(message)

      if html.nil?
        log(:error, "No se encontró contenido HTML en mensaje #{message_id}")
      else
        log(:debug, "HTML extraído exitosamente: #{html.size} bytes")
      end

      html
    rescue Google::Apis::Error => e
      log(:error, "Error al obtener mensaje #{message_id}: #{e.message}")
      nil
    end

    private

    def authorize_with_loopback(authorizer, user_id)
      server = TCPServer.new(LOOPBACK_HOST, 0)
      base_url = "http://#{LOOPBACK_HOST}:#{server.addr[1]}"
      url = authorizer.get_authorization_url(base_url: base_url)

      log(:info, 'Se requiere autorización de Gmail')
      if try_open_browser(url)
        log(:info, 'Navegador abierto. Por favor autoriza la aplicación.')
      else
        log(:warn, "No se pudo abrir el navegador. Abrí esta URL: #{url}")
      end

      code = wait_for_authorization_code(server)
      authorizer.get_and_store_credentials_from_code(user_id: user_id, code: code, base_url: base_url)
    ensure
      server&.close
    end

    def wait_for_authorization_code(server)
      deadline = Time.now + AUTH_TIMEOUT
      loop do
        remaining = deadline - Time.now
        ready = remaining.positive? && IO.select([server], nil, nil, remaining)
        raise Error, "No se recibió la autorización en #{AUTH_TIMEOUT} segundos" unless ready

        params = read_callback_params(server.accept)
        raise Error, "Autorización rechazada: #{params['error']}" if params['error']
        return params['code'] if params['code']
      end
    end

    def read_callback_params(client)
      return {} unless IO.select([client], nil, nil, 5)

      path = client.gets.to_s.split[1].to_s
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" \
                   '<p>Listo, ya podés cerrar esta pestaña y volver a la terminal.</p>'
      URI.decode_www_form(URI(path).query.to_s).to_h
    rescue URI::InvalidURIError
      {}
    ensure
      client.close
    end

    def list_all_messages(query)
      messages = []
      page_token = nil
      loop do
        result = @service.list_user_messages('me', q: query, page_token: page_token)
        messages.concat(result.messages || [])
        page_token = result.next_page_token
        log(:debug, "Página con #{result.messages&.size || 0} mensajes, siguiente: #{page_token.inspect}")
        break if page_token.nil?
      end
      messages
    end

    def build_query(date, subject: 'Aviso de compra')
      next_day = date + 1
      [
        'from:info@notificaciones.bancomacro.com.ar',
        %(subject:"#{subject}"),
        "after:#{Time.new(date.year, date.month, date.day).to_i}",
        "before:#{Time.new(next_day.year, next_day.month, next_day.day).to_i}"
      ].join(' ')
    end

    # Extrae la parte HTML del mensaje
    # Usa estrategia híbrida: intenta ruta directa, si falla busca recursivamente
    def extract_html_body(message)
      payload = message.payload

      # Caso 1: El payload mismo es HTML
      return decode_body(payload.body.data) if payload.mime_type == 'text/html' && payload.body.data

      # Caso 2: Buscar en partes del multipart
      if payload.parts
        # Intentar ruta directa común: multipart/related -> text/html
        html = find_html_direct(payload.parts)
        return html if html

        # Si fallo, buscar recursivamente
        html = find_html_recursive(payload.parts)
        return html if html
      end

      nil
    end

    # Busca HTML en la ruta directa esperada (más rápido)
    def find_html_direct(parts)
      log(:debug, "find_html_direct: buscando en #{parts.size} partes")

      parts.each do |part|
        log(:debug, "Parte: mime_type=#{part.mime_type}, tiene parts? #{!part.parts.nil?}")

        next unless part.mime_type == 'multipart/related' && part.parts

        log(:debug, "Encontrado multipart/related con #{part.parts.size} subpartes")

        part.parts.each do |subpart|
          log(:debug, "Subparte: mime_type=#{subpart.mime_type}, body.data existe? #{!subpart.body.data.nil?}")

          if subpart.mime_type == 'text/html' && subpart.body.data
            log(:debug, 'Encontrado text/html, intentando decodificar...')
            return decode_body(subpart.body.data)
          end
        end
      end
      nil
    end

    # Busca HTML recursivamente en todo el árbol (fallback)
    def find_html_recursive(parts)
      log(:debug, "find_html_recursive: buscando en #{parts.size} partes")

      parts.each do |part|
        log(:debug, "Parte recursiva: mime_type=#{part.mime_type}, body.data existe? #{!part.body.data.nil?}")

        if part.mime_type == 'text/html' && part.body.data
          log(:debug, 'Encontrado text/html en búsqueda recursiva, intentando decodificar...')
          return decode_body(part.body.data)
        end

        next unless part.parts

        log(:debug, 'Parte tiene subpartes, buscando recursivamente...')
        html = find_html_recursive(part.parts)
        return html if html
      end
      nil
    end

    def decode_body(data)
      return nil if data.nil? || data.empty?

      data.dup.force_encoding('UTF-8')
    end

    # Intenta abrir el navegador automáticamente
    def try_open_browser(url)
      case RbConfig::CONFIG['host_os']
      when /linux/
        system('xdg-open', url, out: File::NULL, err: File::NULL)
      when /darwin/
        system('open', url, out: File::NULL, err: File::NULL)
      when /mswin|mingw|cygwin/
        system('start', url, out: File::NULL, err: File::NULL)
      else
        false
      end
    rescue StandardError
      false
    end

    # Helper para logging
    def log(level, message)
      return unless @logger

      case level
      when :debug
        @logger.debug(message)
      when :info
        @logger.info(message)
      when :warn
        @logger.warn(message)
      when :error
        @logger.error(message)
      when :fatal
        @logger.fatal(message)
      end
    end
  end
end
