# frozen_string_literal: true

module Boton
  class TransactionPresenter
    # Initialize presenter
    # @param logger [Logger] optional logger instance
    def initialize(logger: nil)
      @logger = logger
    end

    # Display transactions in a formatted table
    # @param transactions [Array<Hash>] array of transaction hashes
    # @param summary [Hash, nil] optional summary info with periodo_inicio and periodo_fin
    # @return [nil]
    def display(transactions, summary: nil)
      if transactions.empty?
        puts "\nNo se encontraron transacciones\n\n"
        return
      end

      # Display summary period if provided
      if summary
        inicio = summary['periodo_inicio']
        fin = summary['periodo_fin'] || '(abierto)'
        puts "\nResumen: #{inicio} → #{fin}\n"
      end

      # Header
      puts '=' * 80
      puts format('%-12s %-8s %-13s  %-40s',
                  'FECHA', 'HORA', 'MONTO', 'COMERCIO')
      puts '=' * 80

      # Rows
      total = 0
      transactions.each do |tx|
        puts format('%-12s %-8s $%12.2f  %-40s',
                    tx['transaction_date'],
                    tx['transaction_time'],
                    tx['amount_cents'] / 100.0,
                    tx['merchant'][0..39] # Truncate if too long
                   )
        total += tx['amount_cents']
      end

      # Footer
      puts '=' * 80
      puts format('TOTAL: $%.2f (%d transacciones)', total / 100.0, transactions.size)
      puts '=' * 80 + "\n"
    end
  end
end
