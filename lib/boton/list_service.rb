# frozen_string_literal: true

module Boton
  class ListService
    # Initialize service
    # @param logger [Logger] optional logger instance
    def initialize(logger: nil)
      @logger = logger
    end

    # Execute list operation
    # @param db [Database] database instance
    # @param presenter [TransactionPresenter] presenter instance
    # @param search_term [String, nil] optional search term for merchant
    # @param summary_id [Integer, nil] optional summary_id to filter by (for 'list' command)
    # @param show_all [Boolean] if true, search in all transactions (for 'all' command)
    # @param date [Date, nil] optional date to filter by ('all' or 'list' with date)
    # @return [nil]
    def execute(db, presenter, search_term: nil, summary_id: nil, show_all: false, date: nil)
      if show_all
        display_all(db, presenter, search_term, date)
      else
        display_summary(db, presenter, summary_id, search_term, date)
      end
    end

    # Mostrar transacciones de un rango de fechas dentro del resumen
    # @param db [Database] database instance
    # @param presenter [TransactionPresenter] presenter instance
    # @param summary_id [Integer] id del resumen
    # @param date_start [Date] fecha inicial (inclusive)
    # @param date_end [Date] fecha final (inclusive)
    # @return [nil]
    def execute_range(db, presenter, summary_id, date_start, date_end)
      transactions = db.transactions_by_date_range_in_summary(summary_id, date_start.to_s, date_end.to_s)
      puts "\nTransacciones del resumen del #{date_start} al #{date_end}:"

      summary = db.get_summary_by_id(summary_id)
      presenter.display(transactions, summary: summary)
    end

    private

    # 'all' command: search in all transactions
    # @return [nil]
    def display_all(db, presenter, search_term, date)
      if date
        transactions = db.transactions_by_date(date.to_s)
        puts "\nTransacciones del #{date}:"
      elsif search_term
        transactions = db.search_transactions_by_merchant(search_term)
        puts "\nTransacciones que contienen '#{search_term}':"
      else
        transactions = db.all_transactions
        puts "\nTodas las transacciones:"
      end
      presenter.display(transactions)
    end

    # 'list' command: search in current summary
    # @return [nil]
    def display_summary(db, presenter, summary_id, search_term, date)
      if date
        transactions = db.transactions_by_date_in_summary(summary_id, date.to_s)
        puts "\nTransacciones del resumen del #{date}:"
      elsif search_term
        transactions = db.search_transactions_by_merchant_in_summary(summary_id, search_term)
        puts "\nTransacciones del resumen que contienen '#{search_term}':"
      else
        transactions = db.transactions_by_summary(summary_id)
        puts "\nTransacciones del resumen:"
      end

      # Get summary info to display period
      summary = db.get_summary_by_id(summary_id)
      presenter.display(transactions, summary: summary)
      warn_date_outside_summary(date, summary) if date && transactions.empty?
    end

    # Avisar cuando la fecha consultada cae fuera del período del resumen
    # @param date [Date] fecha consultada
    # @param summary [Hash, nil] resumen actual
    # @return [nil]
    def warn_date_outside_summary(date, summary)
      return unless summary

      date_str = date.to_s
      inicio = summary['periodo_inicio']
      fin = summary['periodo_fin']
      return unless date_str < inicio || (fin && date_str >= fin)

      puts "La fecha #{date_str} está fuera del resumen (#{inicio} → #{fin || '(abierto)'})."
      puts "Usá 'boton all #{date_str}' para buscar en todo el historial.\n\n"
    end
  end
end
