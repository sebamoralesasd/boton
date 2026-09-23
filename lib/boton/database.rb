# frozen_string_literal: true

require 'sqlite3'

module Boton
  class Database
    DEFAULT_PATH = File.expand_path('../../data/transactions.db', __dir__)
    MIGRATIONS = %i[create_base_schema migrate_amount_to_cents create_reversals].freeze

    def initialize(db_path = ENV.fetch('BOTON_DB', DEFAULT_PATH))
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      migrate
      @db.execute('PRAGMA foreign_keys = ON')
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
          INSERT INTO transactions (amount_cents, merchant, transaction_date, transaction_time, email_id, summary_id)
          VALUES (?, ?, ?, ?, ?, ?)
        SQL
        [
          transaction.amount_cents,
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
    def close_summary(summary_id, periodo_fin)
      @db.execute(
        'UPDATE resumenes SET periodo_fin = ? WHERE id = ?',
        [periodo_fin, summary_id]
      )
    end

    def open_summary(periodo_inicio)
      @db.transaction do
        previous = get_open_summary
        close_summary(previous['id'], periodo_inicio) if previous
        id = create_summary(periodo_inicio)
        moved = previous ? move_transactions(previous['id'], id, periodo_inicio) : 0
        { id: id, closed: previous, moved: moved }
      end
    end

    def overlapping_summary(periodo_inicio)
      @db.execute(
        <<~SQL,
          SELECT id, periodo_inicio, periodo_fin
          FROM resumenes
          WHERE periodo_inicio >= ? OR periodo_fin > ?
          ORDER BY periodo_inicio
          LIMIT 1
        SQL
        [periodo_inicio, periodo_inicio]
      ).first
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
          ORDER BY periodo_inicio DESC
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
            amount_cents,
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
          amount_cents,
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
            amount_cents,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE LOWER(merchant) LIKE LOWER(?) ESCAPE '\\' AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        like_pattern(search_term)
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
            amount_cents,
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
            amount_cents,
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
            amount_cents,
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
            amount_cents,
            merchant,
            transaction_date,
            transaction_time,
            email_id,
            summary_id,
            created_at
          FROM transactions
          WHERE summary_id = ? AND LOWER(merchant) LIKE LOWER(?) ESCAPE '\\' AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        [summary_id, like_pattern(search_term)]
      )
    end

    def insert_reversal(reversal)
      @db.execute(
        <<~SQL,
          INSERT INTO reversals (email_id, merchant, amount_cents, reversal_date)
          VALUES (?, ?, ?, ?)
        SQL
        [reversal.email_id, reversal.merchant, reversal.amount_cents, reversal.transaction_date]
      )
      true
    rescue SQLite3::ConstraintException
      false
    end

    def reversal_known?(email_id)
      @db.get_first_value('SELECT COUNT(*) FROM reversals WHERE email_id = ?', email_id).positive?
    end

    def pending_reversals
      @db.execute(
        <<~SQL
          SELECT id, email_id, merchant, amount_cents, reversal_date
          FROM reversals
          WHERE transaction_id IS NULL
          ORDER BY reversal_date
        SQL
      )
    end

    def unreversed_candidates(merchant, amount_cents, before_date)
      @db.execute(
        <<~SQL,
          SELECT id, amount_cents, merchant, transaction_date, transaction_time, email_id, summary_id
          FROM transactions
          WHERE merchant = ? AND amount_cents = ? AND transaction_date <= ? AND reversed_at IS NULL
          ORDER BY transaction_date DESC, transaction_time DESC
        SQL
        [merchant, amount_cents, before_date]
      )
    end

    def apply_reversal(reversal, transaction_id)
      @db.transaction do
        @db.execute(
          'UPDATE transactions SET reversed_at = ?, reversed_by_email_id = ? WHERE id = ?',
          [reversal['reversal_date'], reversal['email_id'], transaction_id]
        )
        @db.execute('UPDATE reversals SET transaction_id = ? WHERE id = ?', [transaction_id, reversal['id']])
      end
    end

    private

    def migrate
      version = @db.get_first_value('PRAGMA user_version')
      MIGRATIONS.each.with_index(1) do |migration, target|
        next if target <= version

        @db.transaction do
          send(migration)
          @db.execute("PRAGMA user_version = #{target}")
        end
      end
    end

    def create_base_schema
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

    def migrate_amount_to_cents
      @db.execute_batch(
        <<~SQL
          CREATE TABLE transactions_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount_cents INTEGER NOT NULL,
            merchant TEXT NOT NULL,
            transaction_date DATE NOT NULL,
            transaction_time TIME NOT NULL,
            email_id TEXT UNIQUE NOT NULL,
            summary_id INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            reversed_at DATE,
            reversed_by_email_id TEXT,
            FOREIGN KEY (summary_id) REFERENCES resumenes(id)
          );
          INSERT INTO transactions_new (
            id, amount_cents, merchant, transaction_date, transaction_time,
            email_id, summary_id, created_at, reversed_at, reversed_by_email_id
          )
          SELECT
            id, CAST(ROUND(amount * 100) AS INTEGER), merchant, transaction_date, transaction_time,
            email_id, summary_id, created_at, reversed_at, reversed_by_email_id
          FROM transactions;
          DROP TABLE transactions;
          ALTER TABLE transactions_new RENAME TO transactions;
          CREATE INDEX idx_transaction_date ON transactions(transaction_date);
          CREATE INDEX idx_summary_id ON transactions(summary_id);
        SQL
      )
    end

    def create_reversals
      @db.execute_batch(
        <<~SQL
          CREATE TABLE reversals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email_id TEXT UNIQUE NOT NULL,
            merchant TEXT NOT NULL,
            amount_cents INTEGER NOT NULL,
            reversal_date DATE NOT NULL,
            transaction_id INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (transaction_id) REFERENCES transactions(id)
          );
          CREATE INDEX idx_reversals_transaction_id ON reversals(transaction_id);
          INSERT INTO reversals (email_id, merchant, amount_cents, reversal_date, transaction_id)
          SELECT reversed_by_email_id, merchant, amount_cents, reversed_at, id
          FROM transactions
          WHERE reversed_by_email_id IS NOT NULL;
        SQL
      )
    end

    def move_transactions(from_summary_id, to_summary_id, since_date)
      @db.execute(
        'UPDATE transactions SET summary_id = ? WHERE summary_id = ? AND transaction_date >= ?',
        [to_summary_id, from_summary_id, since_date]
      )
      @db.changes
    end

    def like_pattern(term)
      "%#{term.gsub(/[\\%_]/) { |char| "\\#{char}" }}%"
    end

    def add_column_if_missing(table, column, type)
      columns = @db.execute("PRAGMA table_info(#{table})").map { |c| c['name'] }
      return if columns.include?(column)

      @db.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
    end
  end
end
