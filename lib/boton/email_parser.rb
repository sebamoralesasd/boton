# frozen_string_literal: true

require_relative 'transaction'

module Boton
  class EmailParser
    # Monto: buscar patrón "$ </span> <span>19.390,00</span>"
    AMOUNT_REGEX = %r{\$\s*</span>\s*<span>([\d.,]+)</span>}m

    # Comercio: buscar "en el establecimiento <b><span>NOMBRE</span>"
    MERCHANT_REGEX = %r{en el establecimiento\s*<b[^>]*><span>([^<]+)</span>}mi

    # Fecha: buscar "el día <b><span>03/01/2026</b>"
    DATE_REGEX = %r{el d(?:í|&iacute;)a\s*<b[^>]*><span>(\d{2}/\d{2}/\d{4})</b>}mi

    # Hora: buscar "a las <b><span>11:39hs</span>"
    TIME_REGEX = %r{a las\s*<b[^>]*><span>(\d{2}:\d{2})hs</span>}mi

    def initialize(logger: nil)
      @logger = logger
    end

    # Parsear email y retornar objeto Transaction
    # @param email_body [String] contenido HTML del email
    # @param email_id [String] Message-ID del email
    # @return [Transaction, nil] objeto Transaction o nil si falla el parseo
    def parse(email_body, email_id)
      # Decodificar quoted-printable si es necesario
      decoded_body = decode_quoted_printable(email_body)

      # Extraer datos usando regexes
      data = extract_data(decoded_body)

      # Verificar que se encontraron todos los campos
      if data[:amount].nil? || data[:merchant].nil? || data[:date].nil? || data[:time].nil?
        log_error("Datos incompletos en email #{email_id}: #{data.inspect}")
        return nil
      end

      # Crear objeto Transaction
      Transaction.new(
        amount: data[:amount],
        merchant: data[:merchant],
        date: data[:date],
        time: data[:time],
        email_id: email_id
      )
    rescue StandardError => e
      log_error("Error parseando email #{email_id}: #{e.class} - #{e.message}")
      log_error(e.backtrace.first(3).join("\n")) if @logger&.debug?
      nil
    end

    private

    # Decodificar quoted-printable encoding
    # @param text [String] texto con encoding quoted-printable
    # @return [String] texto decodificado
    def decode_quoted_printable(text)
      # Forzar encoding a ASCII-8BIT para trabajar con bytes
      text = text.dup.force_encoding('ASCII-8BIT')
      return text.force_encoding('UTF-8').scrub('?') unless text.include?('=3D')

      # Decodificar =3D → =, etc.
      text = text.gsub(/=([0-9A-F]{2})/i) { [::Regexp.last_match(1).hex].pack('C') }

      # Eliminar soft line breaks (=\n y =\r\n)
      text = text.gsub(/=\r?\n/, '')

      # Forzar a UTF-8 y manejar caracteres inválidos
      text.force_encoding('UTF-8')
      text.scrub('?') # Reemplazar bytes inválidos con '?'
    end

    # Extraer todos los datos del HTML
    # @param html [String] contenido HTML del email
    # @return [Hash] hash con los datos extraídos
    def extract_data(html)
      {
        amount: extract_amount(html),
        merchant: extract_merchant(html),
        date: extract_date(html),
        time: extract_time(html)
      }
    end

    # Extraer monto del HTML
    # @param html [String] contenido HTML
    # @return [String, nil] monto en formato "$19.390,00" o nil
    def extract_amount(html)
      match = html.match(AMOUNT_REGEX)
      match ? "$#{match[1]}" : nil
    end

    # Extraer comercio del HTML
    # @param html [String] contenido HTML
    # @return [String, nil] nombre del comercio o nil
    def extract_merchant(html)
      match = html.match(MERCHANT_REGEX)
      match ? match[1] : nil
    end

    # Extraer fecha del HTML
    # @param html [String] contenido HTML
    # @return [String, nil] fecha en formato "03/01/2026" o nil
    def extract_date(html)
      match = html.match(DATE_REGEX)
      match ? match[1] : nil
    end

    # Extraer hora del HTML
    # @param html [String] contenido HTML
    # @return [String, nil] hora en formato "11:39hs" o nil
    def extract_time(html)
      match = html.match(TIME_REGEX)
      match ? "#{match[1]}hs" : nil
    end

    # Helper para logging
    def log_error(message)
      @logger&.error(message)
    end
  end
end
