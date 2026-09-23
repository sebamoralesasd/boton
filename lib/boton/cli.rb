# frozen_string_literal: true

require 'logger'

module Boton
  class CLI
    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      logger = build_logger
      db = Database.new
      app = Application.new(db, logger)
      app.run(argv)
    rescue Interrupt
      logger.warn "\nProcesamiento interrumpido por el usuario"
      exit 130
    rescue UsageError => e
      logger.error e.message
      logger.error "Usa 'boton help' para ver ayuda"
      exit 1
    rescue Error => e
      logger.error e.message
      exit 1
    rescue StandardError => e
      logger.fatal "Error inesperado: #{e.class} - #{e.message}"
      logger.fatal e.backtrace.first(5).join("\n") if e.backtrace
      exit 1
    ensure
      db&.close
    end

    private

    def build_logger
      logger = Logger.new($stdout)
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      level = ENV.fetch('BOTON_LOG_LEVEL', 'INFO')
      begin
        logger.level = level
      rescue ArgumentError
        logger.level = Logger::INFO
        logger.warn "BOTON_LOG_LEVEL inválido (#{level}), usando INFO"
      end
      logger
    end
  end
end
