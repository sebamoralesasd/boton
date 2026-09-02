# frozen_string_literal: true

require 'date'

module Boton
  class ReversalService
    # Execute reversal detection
    # @param date [Date] date to search reversals for
    # @param db [Database] database instance
    # @param gmail_client [GmailClient] Gmail client instance
    # @param email_parser [EmailParser] email parser instance
    # @param logger [Logger] logger instance
    # @return [Hash] stats hash with :total, :matched, :unmatched, :duplicates, :errors
    def initialize(logger: nil)
      @logger = logger
    end

    def execute(date, db, gmail_client, email_parser)
      log_info "Buscando reversos para fecha: #{date}"

      stats = { total: 0, matched: 0, unmatched: 0, duplicates: 0, errors: 0 }

      messages = gmail_client.fetch_reversals(date)

      messages.each do |msg|
        stats[:total] += 1

        if db.reversal_processed?(msg.id)
          log_warn "Reverso ya procesado, saltando: #{msg.id}"
          stats[:duplicates] += 1
          next
        end

        html = gmail_client.get_message_content(msg.id)
        if html.nil?
          log_error "No se pudo obtener HTML del mensaje: #{msg.id}"
          stats[:errors] += 1
          next
        end

        reversal = email_parser.parse(html, msg.id)
        if reversal.nil?
          stats[:errors] += 1
          next
        end

        original = db.find_unreversed_transaction_by_merchant_and_amount(
          reversal.merchant, reversal.amount, before_date: reversal.transaction_date
        )

        if original
          db.mark_transaction_reversed(original['id'], reversal.email_id, reversal.transaction_date)
          log_info "Reverso: $#{reversal.amount} en #{reversal.merchant} -> anula transacción " \
                    "##{original['id']} (#{original['transaction_date']} #{original['transaction_time']})"
          stats[:matched] += 1
        else
          log_warn "Reverso sin transacción original en la DB: $#{reversal.amount} en #{reversal.merchant} " \
                    "(#{reversal.transaction_date})"
          stats[:unmatched] += 1
        end
      end

      # Log summary
      log_info '=== RESUMEN REVERSOS ==='
      log_info "Reversos encontrados: #{stats[:total]}"
      log_info "Coincidencias: #{stats[:matched]}"
      log_info "Sin coincidencia: #{stats[:unmatched]}"
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
