# frozen_string_literal: true

require 'sqlite3'

module Boton
  class Database
    DEFAULT_PATH = File.expand_path('../../data/transactions.db', __dir__)

    def initialize(db_path = ENV.fetch('BOTON_DB', DEFAULT_PATH))
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      setup_schema
    end

    attr_reader :db

    def close
      @db.close if @db && !@db.closed?
    end

    # Insertar transacción con manejo de duplicados
    # @param transaction [Transaction] objeto Transaction con datos validados
    # @return [Boolean] true si se insertó, false si falló
    def insert_transaction(transaction)
      @db.execute(
        <<~SQL,
          INSERT INTO transactions (amount, merchant, transaction_date, transaction_time, email_id, summary_id)
          VALUES (?, ?, ?, ?, ?, ?)
        SQL
        [
          transaction.amount,
          transaction.merchant,
          transaction.transaction_date,
          transaction.transaction_time,
          transaction.email_id,
          transaction.summary_id
        ]
      )
      true
    rescue SQLite3::ConstraintException
      # Email duplicado - constraint UNIQUE en email_id
      false
    end

    # Crear un nuevo resumen (período)
    # @param periodo_inicio [String] fecha de inicio en formato 'YYYY-MM-DD'
    # @param periodo_fin [String, nil] fecha de fin en formato 'YYYY-MM-DD' o nil para resumen abierto
    # @return [Integer] id del resumen creado
    def create_summary(periodo_inicio, periodo_fin = nil)
      @db.execute(
        <<~SQL,
          INSERT INTO resumenes (periodo_inicio, periodo_fin)
          VALUES (?, ?)
        SQL
        [periodo_inicio, periodo_fin]
      )
      @db.last_insert_row_id
    end

    # Obtener el resumen abierto (más reciente sin periodo_fin)
    # @return [Hash, nil] resumen abierto o nil si no existe
    def get_open_summary
      result = @db.execute(
        <<~SQL
          SELECT#{' '}
            id,
            periodo_inicio,
            periodo_fin,
            created_at
          FROM resumenes
          WHERE periodo_fin IS NULL
          ORDER BY id DESC
          LIMIT 1
        SQL
      )
      result.first
    end

    # Obtener un resumen por su ID
    # @param summary_id [Integer] id del resumen
    # @return [Hash, nil] resumen encontrado o nil
    def get_summary_by_id(summary_id)
      result = @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            periodo_inicio,
            periodo_fin,
            created_at
          FROM resumenes
          WHERE id = ?
        SQL
        summary_id
      )
      result.first
    end

    # Cerrar un resumen (asignar periodo_fin)
    # @param summary_id [Integer] id del resumen
    # @param periodo_fin [String] fecha de cierre en formato 'YYYY-MM-DD'
    # @return [Boolean] true si se cerró, false si falló
    def close_summary(summary_id, periodo_fin)
      @db.execute(
        'UPDATE resumenes SET periodo_fin = ? WHERE id = ?',
        [periodo_fin, summary_id]
      )
      true
    rescue StandardError
      false
    end

    # Buscar resumen por fecha de transacción
    # @param transaction_date [String] fecha de la transacción en formato 'YYYY-MM-DD'
    # @return [Hash, nil] resumen donde periodo_inicio <= transaction_date < periodo_fin, o nil
    # Si periodo_fin IS NULL (resumen abierto), acepta cualquier fecha >= periodo_inicio
    def find_summary_by_dates(transaction_date)
      result = @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            periodo_inicio,
            periodo_fin,
            created_at
          FROM resumenes
          WHERE periodo_inicio <= ? AND (periodo_fin IS NULL OR ? < periodo_fin)
          LIMIT 1
        SQL
        [transaction_date, transaction_date]
      )
      result.first
    end

    # Verificar si un email ya fue procesado
    # @param email_id [String] Message-ID del email
    # @return [Boolean] true si ya existe en la base de datos
    def transaction_processed?(email_id)
      result = @db.execute(
        'SELECT COUNT(*) as count FROM transactions WHERE email_id = ?',
        email_id
      )
      result.first['count'].positive?
    end

    # Consultar transacciones de una fecha específica
    # @param date [String] fecha en formato 'YYYY-MM-DD'
    # @return [Array<Hash>] array de transacciones
    def transactions_by_date(date)
      @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE transaction_date = ? AND reversed_at IS NULL
          ORDER BY transaction_time DESC
        SQL
        date
      )
    end

    # Obtener todas las transacciones (ordenadas por fecha desc)
    # @param limit [Integer] límite opcional de resultados
    # @return [Array<Hash>] array de transacciones
    def all_transactions(limit: nil)
      sql = <<~SQL
        SELECT
          id,
          amount,
          merchant,
          transaction_date,
          transaction_time,
          email_id,
          summary_id,
          created_at
        FROM transactions
        WHERE reversed_at IS NULL
        ORDER BY transaction_date DESC, transaction_time DESC
      SQL
      sql += " LIMIT #{limit}" if limit
      @db.execute(sql)
    end

    # Búsqueda transacciones por palabra clave en merchant (case-insensitive)
    # @param search_term [String] palabra clave a buscar
    # @return [Array<Hash>] array de transacciones coincidentes
    def search_transactions_by_merchant(search_term)
      @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE LOWER(merchant) LIKE '%' || LOWER(?) || '%' AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        search_term
      )
    end

    # Obtener transacciones de un resumen específico
    # @param summary_id [Integer] id del resumen
    # @return [Array<Hash>] array de transacciones del resumen
    def transactions_by_summary(summary_id)
      @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE summary_id = ? AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        summary_id
      )
    end

    # Obtener transacciones de una fecha dentro de un resumen específico
    # @param summary_id [Integer] id del resumen
    # @param date [String] fecha en formato 'YYYY-MM-DD'
    # @return [Array<Hash>] array de transacciones del resumen en esa fecha
    def transactions_by_date_in_summary(summary_id, date)
      @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE summary_id = ? AND transaction_date = ? AND reversed_at IS NULL
          ORDER BY transaction_time DESC
        SQL
        [summary_id, date]
      )
    end

    # Obtener transacciones de un rango de fechas dentro de un resumen específico
    # @param summary_id [Integer] id del resumen
    # @param date_start [String] fecha inicial en formato 'YYYY-MM-DD' (inclusive)
    # @param date_end [String] fecha final en formato 'YYYY-MM-DD' (inclusive)
    # @return [Array<Hash>] array de transacciones del resumen en ese rango
    def transactions_by_date_range_in_summary(summary_id, date_start, date_end)
      @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE summary_id = ? AND transaction_date BETWEEN ? AND ? AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        [summary_id, date_start, date_end]
      )
    end

    # Buscar transacciones por palabra clave dentro de un resumen (case-insensitive)
    # @param summary_id [Integer] id del resumen
    # @param search_term [String] palabra clave a buscar
    # @return [Array<Hash>] array de transacciones coincidentes
    def search_transactions_by_merchant_in_summary(summary_id, search_term)
      @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE summary_id = ? AND LOWER(merchant) LIKE '%' || LOWER(?) || '%' AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        [summary_id, search_term]
      )
    end

    # Verificar si un reverso ya fue procesado (idempotencia)
    # @param email_id [String] Message-ID del email de reverso
    # @return [Boolean] true si ya se marcó una transacción con este reverso
    def reversal_processed?(email_id)
      result = @db.execute(
        'SELECT COUNT(*) as count FROM transactions WHERE reversed_by_email_id = ?',
        email_id
      )
      result.first['count'].positive?
    end

    # Buscar transacción original no reversada, por comercio y monto exactos
    # @param merchant [String] nombre del comercio (normalizado)
    # @param amount [Float] monto de la transacción
    # @param before_date [String] fecha del reverso en formato 'YYYY-MM-DD'
    # @return [Hash, nil] transacción encontrada o nil
    def find_unreversed_transaction_by_merchant_and_amount(merchant, amount, before_date:)
      result = @db.execute(
        <<~SQL,
          SELECT#{' '}
            id,
            amount,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE merchant = ? AND amount = ? AND transaction_date <= ? AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
          LIMIT 1
        SQL
        [merchant, amount, before_date]
      )
      result.first
    end

    # Marcar una transacción como reversada
    # @param transaction_id [Integer] id de la transacción original
    # @param reversal_email_id [String] Message-ID del email de reverso
    # @param reversal_date [String] fecha del reverso en formato 'YYYY-MM-DD'
    # @return [Boolean] true
    def mark_transaction_reversed(transaction_id, reversal_email_id, reversal_date)
      @db.execute(
        'UPDATE transactions SET reversed_at = ?, reversed_by_email_id = ? WHERE id = ?',
        [reversal_date, reversal_email_id, transaction_id]
      )
      true
    end

    private

    def setup_schema
      @db.execute(
        <<~SQL
          CREATE TABLE IF NOT EXISTS resumenes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            periodo_inicio DATE NOT NULL,
            periodo_fin DATE,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        SQL
      )

      @db.execute(
        <<~SQL
          CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount DECIMAL(10,2) NOT NULL,
            merchant TEXT NOT NULL,
            transaction_date DATE NOT NULL,
            transaction_time TIME NOT NULL,
            email_id TEXT UNIQUE NOT NULL,
            summary_id INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (summary_id) REFERENCES resumenes(id)
          )
        SQL
      )

      @db.execute('CREATE INDEX IF NOT EXISTS idx_transaction_date ON transactions(transaction_date)')
      @db.execute('CREATE INDEX IF NOT EXISTS idx_email_id ON transactions(email_id)')
      @db.execute('CREATE INDEX IF NOT EXISTS idx_resumen_dates ON resumenes(periodo_inicio, periodo_fin)')

      add_column_if_missing('transactions', 'reversed_at', 'DATE')
      add_column_if_missing('transactions', 'reversed_by_email_id', 'TEXT')
    end

    def add_column_if_missing(table, column, type)
      columns = @db.execute("PRAGMA table_info(#{table})").map { |c| c['name'] }
      return if columns.include?(column)

      @db.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
    end
  end
end
