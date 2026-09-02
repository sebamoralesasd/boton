# frozen_string_literal: true

require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'base64'

module Boton
  class GmailClient
    SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_READONLY
    OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
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
        url = authorizer.get_authorization_url(base_url: OOB_URI)

        log(:info, 'Se requiere autorización de Gmail')
        log(:info, 'Abriendo navegador para autorización...')

        # Intentar abrir navegador automáticamente
        if try_open_browser(url)
          log(:info, 'Navegador abierto. Por favor autoriza la aplicación.')
        else
          log(:warn, 'No se pudo abrir el navegador automáticamente')
          puts "\nPor favor abre esta URL en tu navegador:"
          puts url
        end

        puts "\nIngresa el código de autorización:"
        code = STDIN.gets.chomp

        credentials = authorizer.get_and_store_credentials_from_code(
          user_id: user_id,
          code: code,
          base_url: OOB_URI
        )

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

      result = @service.list_user_messages('me', q: query)
      messages = result.messages || []

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

      result = @service.list_user_messages('me', q: query)
      messages = result.messages || []

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

    # Construye el query de búsqueda para Gmail
    def build_query(date, subject: 'Aviso de compra')
      next_day = date + 1
      [
        'from:info@notificaciones.bancomacro.com.ar',
        %(subject:"#{subject}"),
        "after:#{date.strftime('%Y/%m/%d')}",
        "before:#{next_day.strftime('%Y/%m/%d')}"
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

    # Decodifica el cuerpo del mensaje (Base64 URL-safe o texto plano)
    def decode_body(encoded_data)
      log(:debug, "decode_body llamado con: #{encoded_data.class}")
      log(:debug,
          "encoded_data nil? #{encoded_data.nil?}, empty? #{encoded_data.respond_to?(:empty?) ? encoded_data.empty? : 'N/A'}")

      return nil if encoded_data.nil? || encoded_data.empty?

      if encoded_data.respond_to?(:size)
        preview = encoded_data.to_s[0..100]
        log(:debug, "Primeros 100 chars: #{preview.inspect}")
      end

      # Verificar si el contenido ya está decodificado (empieza con HTML)
      trimmed = encoded_data.strip
      if trimmed.start_with?('<')
        log(:debug, 'Contenido ya está decodificado (HTML), retornando directo')
        return encoded_data.force_encoding('UTF-8')
      end

      # Intentar decodificar Base64
      log(:debug, 'Intentando decodificar Base64...')
      decoded = Base64.urlsafe_decode64(encoded_data)
      log(:debug, 'Base64 decodificado exitosamente')
      decoded.force_encoding('UTF-8')
    rescue ArgumentError => e
      # Si falla Base64, asumir que ya está decodificado
      log(:warn, "Error decodificando Base64: #{e.message}, usando contenido sin decodificar")
      encoded_data.force_encoding('UTF-8')
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
