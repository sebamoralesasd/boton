# frozen_string_literal: true

require 'date'

module Boton
  class CommandParser
    # Parse command line arguments and return action hash
    # @param args [Array<String>] command line arguments
    # @return [Hash] hash with :action and optional :date keys
    def self.parse(args)
      new.parse(args)
    end

    # Instance method for parsing
    # @param args [Array<String>] command line arguments
    # @return [Hash] hash with :action and optional :date keys
    def parse(args)
      args = args.dup
      local = !args.delete('--local').nil?
      command = args[0]

      case command
      when nil
        # Sin argumentos: sync hoy
        { action: :sync, date: Date.today, local: local }

      when 'list'
        # Mostrar transacciones del resumen actual
        if args[1]
          if date_argument?(args[1])
            # Es una fecha o palabra clave: filtrar el resumen por ese día
            { action: :list, date: parse_date_or_keyword(args[1]), search_term: nil }
          else
            # Es una palabra clave de búsqueda
            { action: :list, search_term: args[1], date: nil }
          end
        else
          { action: :list, search_term: nil, date: nil }
        end

      when 'all'
        # Mostrar todas las transacciones
        if args[1]
          # Intenta parsear como fecha YYYY-MM-DD
          if args[1].match?(/^\d{4}-\d{2}-\d{2}$/)
            date = Date.parse(args[1])
            { action: :all, date: date, search_term: nil }
          else
            # Es una palabra clave de búsqueda
            { action: :all, search_term: args[1] }
          end
        else
          { action: :all, search_term: nil }
        end

      when 'help', '-h', '--help'
        { action: :help }

      when 'ayer'
        # Sincronizar transacciones de ayer
        { action: :sync, date: Date.today - 1, local: local }

      when 'desde'
        # Sincronizar desde una fecha hasta hoy
        if args[1]
          date_start = parse_date_or_keyword(args[1])
          { action: :sync_range, date_start: date_start, date_end: Date.today, local: local }
        else
          { action: :error, message: 'Especificar fecha o palabra clave: boton desde YYYY-MM-DD|ayer' }
        end

      when 'open'
        # Abrir nuevo resumen (cierra el anterior si existe)
        if args[1]
          date = Date.parse(args[1])
          { action: :open, date: date }
        else
          { action: :error, message: 'Especificar fecha: boton open YYYY-MM-DD' }
        end

      when 'reversos'
        # Buscar reversos de una fecha (hoy por defecto) y marcarlos en la DB
        if local
          { action: :error, message: "El comando 'reversos' requiere Gmail y no admite --local" }
        elsif args[1]
          date = Date.parse(args[1])
          { action: :reversos, date: date }
        else
          { action: :reversos, date: Date.today }
        end

      when /^\d{4}-\d{2}-\d{2}$/
        # Fecha directa: sync esa fecha
        { action: :sync, date: Date.parse(command), local: local }

      else
        { action: :help }
      end
    rescue ArgumentError
      { action: :error, message: 'Formato de fecha inválido. Usar: YYYY-MM-DD' }
    end

    private

    # Check if an argument looks like a date (YYYY-MM-DD) or a date keyword
    # @param input [String] argument to check
    # @return [Boolean] true if it can be parsed as a date
    def date_argument?(input)
      %w[ayer hoy].include?(input) || input.match?(/^\d{4}-\d{2}-\d{2}$/)
    end

    # Parse date or keyword (e.g., 'ayer', 'hoy')
    # @param input [String] date string or keyword
    # @return [Date] parsed date
    def parse_date_or_keyword(input)
      case input
      when 'ayer'
        Date.today - 1
      when 'hoy'
        Date.today
      else
        Date.parse(input)
      end
    end
  end
end
