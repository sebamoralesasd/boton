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
        raise UsageError, cmd[:message]
      end
    end

    private

    def execute_sync(date)
      gmail = GmailClient.new(logger: @logger)
      parser = EmailParser.new(logger: @logger)
      service = SyncService.new(logger: @logger)

      service.execute(date, @db, gmail, parser)
      match_pending_reversals
    end

    def execute_range_action(cmd)
      return execute_local_range(cmd[:date_start], cmd[:date_end]) if cmd[:local]

      execute_sync_range(cmd[:date_start], cmd[:date_end])
    end

    def execute_sync_range(date_start, date_end)
      raise UsageError, "No se puede procesar fechas futuras: #{date_start}" if date_start > Date.today
      if date_start > date_end
        raise UsageError, "Fecha de inicio debe ser anterior a fecha de fin: #{date_start} > #{date_end}"
      end

      gmail = GmailClient.new(logger: @logger)
      parser = EmailParser.new(logger: @logger)
      service = SyncService.new(logger: @logger)

      current_date = date_start
      while current_date <= date_end
        service.execute(current_date, @db, gmail, parser)
        current_date += 1
      end
      match_pending_reversals
    end

    def match_pending_reversals
      ReversalService.new(logger: @logger).match_pending(@db)
    end

    # Modo --local: mostrar lo registrado en la base, sin consultar Gmail
    def execute_local(date)
      @logger.info 'Modo --local: no se consulta Gmail'
      execute_list(nil, date)
    end

    # Modo --local para un rango de fechas
    def execute_local_range(date_start, date_end)
      if date_start > date_end
        raise UsageError, "Fecha de inicio debe ser anterior a fecha de fin: #{date_start} > #{date_end}"
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
      raise Error, "No hay resumen para hoy (#{today}). Usa 'boton open YYYY-MM-DD' para crear uno." unless summary

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

      conflict = @db.overlapping_summary(date_str)
      if conflict
        raise Error, "El resumen ##{conflict['id']} (#{conflict['periodo_inicio']} → " \
                     "#{conflict['periodo_fin'] || '(abierto)'}) se superpone con #{date_str}"
      end

      result = @db.open_summary(date_str)
      if result[:closed]
        @logger.info "Summary cerrado: #{result[:closed]['periodo_inicio']} → #{date_str}"
        @logger.info "Transacciones movidas al nuevo summary: #{result[:moved]}"
      end
      @logger.info "Nuevo summary abierto: #{date_str}"
      @logger.info "Summary ID: #{result[:id]}"
    end
  end
end
