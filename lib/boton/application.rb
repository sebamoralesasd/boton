# frozen_string_literal: true

require_relative 'command_parser'
require_relative 'transaction_presenter'
require_relative 'help_presenter'
require_relative 'sync_service'
require_relative 'list_service'
require_relative 'reversal_service'
require_relative 'gmail_client'
require_relative 'email_parser'

module Boton
  class Application
    # Initialize application
    # @param db [Database] database instance
    # @param logger [Logger] logger instance
    def initialize(db, logger)
      @db = db
      @logger = logger
    end

    # Run the application
    # @param argv [Array<String>] command line arguments
    # @return [nil]
    def run(argv)
      cmd = CommandParser.parse(argv)

      case cmd[:action]
      when :sync
        cmd[:local] ? execute_local(cmd[:date]) : execute_sync(cmd[:date])
      when :sync_range
        execute_range_action(cmd)
      when :list
        execute_list(cmd[:search_term], cmd[:date])
      when :all
        execute_all_transactions(cmd[:search_term], cmd[:date])
      when :open
        execute_open_summary(cmd[:date])
      when :reversos
        execute_reversos(cmd[:date])
      when :help
        HelpPresenter.show
      when :error
        @logger.error cmd[:message]
        @logger.error "Usa 'boton help' para ver ayuda"
        exit 1
      end
    end

    private

    def execute_sync(date)
      gmail = GmailClient.new(logger: @logger)
      parser = EmailParser.new(logger: @logger)
      service = SyncService.new(logger: @logger)

      service.execute(date, @db, gmail, parser)
    end

    def execute_range_action(cmd)
      return execute_local_range(cmd[:date_start], cmd[:date_end]) if cmd[:local]

      execute_sync_range(cmd[:date_start], cmd[:date_end])
    end

    def execute_sync_range(date_start, date_end)
      # Validar que no sea fecha futura
      if date_start > Date.today
        @logger.error "No se puede procesar fechas futuras: #{date_start}"
        exit 1
      end

      # Validar que fecha_inicio sea anterior a fecha_fin
      if date_start > date_end
        @logger.error "Fecha de inicio debe ser anterior a fecha de fin: #{date_start} > #{date_end}"
        exit 1
      end

      gmail = GmailClient.new(logger: @logger)
      parser = EmailParser.new(logger: @logger)
      service = SyncService.new(logger: @logger)

      current_date = date_start
      while current_date <= date_end
        service.execute(current_date, @db, gmail, parser)
        current_date += 1
      end
    end

    # Modo --local: mostrar lo registrado en la base, sin consultar Gmail
    def execute_local(date)
      @logger.info 'Modo --local: no se consulta Gmail'
      execute_list(nil, date)
    end

    # Modo --local para un rango de fechas
    def execute_local_range(date_start, date_end)
      if date_start > date_end
        @logger.error "Fecha de inicio debe ser anterior a fecha de fin: #{date_start} > #{date_end}"
        exit 1
      end

      @logger.info 'Modo --local: no se consulta Gmail'
      summary = current_summary_or_exit

      presenter = TransactionPresenter.new(logger: @logger)
      service = ListService.new(logger: @logger)

      service.execute_range(@db, presenter, summary['id'], date_start, date_end)
    end

    def execute_list(search_term = nil, date = nil)
      summary = current_summary_or_exit

      presenter = TransactionPresenter.new(logger: @logger)
      service = ListService.new(logger: @logger)

      service.execute(@db, presenter, search_term: search_term, summary_id: summary['id'], date: date)
    end

    def execute_all_transactions(search_term = nil, date = nil)
      presenter = TransactionPresenter.new(logger: @logger)
      service = ListService.new(logger: @logger)

      service.execute(@db, presenter, search_term: search_term, show_all: true, date: date)
    end

    # Obtener el resumen que contiene la fecha de hoy o terminar con error
    # @return [Hash] resumen vigente
    def current_summary_or_exit
      today = Date.today.to_s
      summary = @db.find_summary_by_dates(today)
      unless summary
        @logger.error "No hay resumen para hoy (#{today}). Usa 'boton open YYYY-MM-DD' para crear uno."
        exit 1
      end
      summary
    end

    def execute_reversos(date)
      gmail = GmailClient.new(logger: @logger)
      parser = EmailParser.new(logger: @logger)
      service = ReversalService.new(logger: @logger)

      service.execute(date, @db, gmail, parser)
    end

    def execute_open_summary(date)
      date_str = date.strftime('%Y-%m-%d')

      # Buscar resumen abierto
      open_summary = @db.get_open_summary
      if open_summary
        # Cerrar resumen anterior
        @db.close_summary(open_summary['id'], date_str)
        @logger.info "Summary cerrado: #{open_summary['periodo_inicio']} → #{date_str}"
      end

      # Crear nuevo resumen
      new_summary_id = @db.create_summary(date_str, nil)
      @logger.info "Nuevo summary abierto: #{date_str}"
      @logger.info "Summary ID: #{new_summary_id}"
    end
  end
end
