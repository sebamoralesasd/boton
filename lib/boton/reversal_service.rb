# frozen_string_literal: true

require 'date'

module Boton
  class ReversalService
    def initialize(logger: nil)
      @logger = logger
    end

    def execute(date, db, gmail_client, email_parser)
      log_info "Buscando reversos para fecha: #{date}"

      stats = { total: 0, new: 0, duplicates: 0, errors: 0 }

      gmail_client.fetch_reversals(date).each do |msg|
        stats[:total] += 1
        stats[register(msg, db, gmail_client, email_parser)] += 1
      end

      match_stats = match_pending(db)

      log_info '=== RESUMEN REVERSOS ==='
      log_info "Reversos encontrados: #{stats[:total]}"
      log_info "Nuevos: #{stats[:new]}"
      log_info "Duplicados: #{stats[:duplicates]}"
      log_info "Errores: #{stats[:errors]}"

      stats.merge(match_stats)
    end

    def match_pending(db)
      stats = { matched: 0, pending: 0, ambiguous: 0 }

      db.pending_reversals.each do |reversal|
        candidates = db.unreversed_candidates(
          reversal['merchant'], reversal['amount_cents'], reversal['reversal_date']
        )
        stats[apply(reversal, candidates, db)] += 1
      end

      unless stats.values.sum.zero?
        log_info "Reversos aplicados: #{stats[:matched]}, " \
                 "sin compra: #{stats[:pending]}, ambiguos: #{stats[:ambiguous]}"
      end
      stats
    end

    private

    def register(msg, db, gmail_client, email_parser)
      if db.reversal_known?(msg.id)
        log_warn "Reverso ya registrado, saltando: #{msg.id}"
        return :duplicates
      end

      html = gmail_client.get_message_content(msg.id)
      if html.nil?
        log_error "No se pudo obtener HTML del mensaje: #{msg.id}"
        return :errors
      end

      reversal = email_parser.parse(html, msg.id)
      return :errors if reversal.nil?

      db.insert_reversal(reversal) ? :new : :duplicates
    end

    def apply(reversal, candidates, db)
      description = "#{money(reversal['amount_cents'])} en #{reversal['merchant']} (#{reversal['reversal_date']})"

      case candidates.size
      when 0
        log_warn "Reverso sin compra original en la DB: #{description}"
        :pending
      when 1
        original = candidates.first
        db.apply_reversal(reversal, original['id'])
        log_info "Reverso: #{description} -> anula transacción " \
                 "##{original['id']} (#{original['transaction_date']} #{original['transaction_time']})"
        :matched
      else
        ids = candidates.map { |tx| "##{tx['id']} (#{tx['transaction_date']} #{tx['transaction_time']})" }
        log_warn "Reverso ambiguo, no se anula nada: #{description}. Candidatas: #{ids.join(', ')}"
        :ambiguous
      end
    end

    def money(cents)
      format('$%.2f', cents / 100.0)
    end

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
