# frozen_string_literal: true

require 'date'

module Boton
  class SyncService
    # Execute sync operation
    # @param date [Date] date to sync
    # @param db [Database] database instance
    # @param gmail_client [GmailClient] Gmail client instance
    # @param email_parser [EmailParser] email parser instance
    # @param logger [Logger] logger instance
    # @return [Hash] stats hash with :total, :inserted, :duplicates, :errors
    def initialize(logger: nil)
      @logger = logger
    end

    def execute(date, db, gmail_client, email_parser)
      # Validar que no sea fecha futura
      if date > Date.today
        log_error "No se puede procesar fechas futuras: #{date}"
        return { total: 0, inserted: 0, duplicates: 0, errors: 0 }
      end

      log_info "Iniciando procesamiento para fecha: #{date}"

      # Statistics
      stats = { total: 0, inserted: 0, duplicates: 0, errors: 0 }

      # Fetch messages from Gmail
      messages = gmail_client.fetch_transactions(date)

      # Process each email
      messages.each do |msg|
        stats[:total] += 1

        # Check if already processed
        if db.transaction_processed?(msg.id)
          log_warn "Email duplicado, saltando: #{msg.id}"
          stats[:duplicates] += 1
          next
        end

        # Get HTML content
        html = gmail_client.get_message_content(msg.id)
        if html.nil?
          log_error "No se pudo obtener HTML del mensaje: #{msg.id}"
          stats[:errors] += 1
          next
        end

        # Parse email
        transaction = email_parser.parse(html, msg.id)
        if transaction.nil?
          stats[:errors] += 1
          next
        end

        # Find summary for this transaction date
        summary = db.find_summary_by_dates(transaction.transaction_date)
        if summary.nil?
          log_error "No existe resumen para la fecha: #{transaction.transaction_date}"
          stats[:errors] += 1
          next
        end

        # Assign summary_id to transaction
        transaction.present[:summary_id] = summary['id']

        # Insert into database
        if db.insert_transaction(transaction)
          amount = format('$%.2f', transaction.amount_cents / 100.0)
          log_info "Transaccion insertada: #{amount} en #{transaction.merchant}"
          stats[:inserted] += 1
        else
          log_error 'Error insertando transaccion (duplicado inesperado)'
          stats[:errors] += 1
        end
      end

      # Log summary
      log_info '=== RESUMEN ==='
      log_info "Emails encontrados: #{stats[:total]}"
      log_info "Nuevas transacciones: #{stats[:inserted]}"
      log_info "Duplicados: #{stats[:duplicates]}"
      log_info "Errores: #{stats[:errors]}"

      stats
    end

    private

    def log_info(message)
      @logger&.info(message)
    end

    def log_warn(message)
      @logger&.warn(message)
    end

    def log_error(message)
      @logger&.error(message)
    end
  end
end
