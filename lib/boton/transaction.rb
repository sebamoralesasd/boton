# frozen_string_literal: true

module Boton
  class Transaction
    # (amount, email_id, date, time, merchant)
    def initialize(params)
      @params = params
      validate
      format
    end

    def present
      @params
    end

    def validate
      raise StandardError if amount.nil? || merchant.nil? || date.nil? || time.nil?
    end

    def format
      format_amount
      format_date
      format_time
      format_merchant
    end

    def format_amount
      @params[:amount] = amount
                         .gsub('$', '') # Quitar símbolo de peso
                         .strip               # Quitar espacios
                         .gsub('.', '')       # Quitar separador de miles
                         .gsub(',', '.')      # Convertir coma decimal a punto
                         .to_f                # Convertir a float
    end

    def format_date
      day, month, year = date.split('/')
      @params[:date] = "#{year}-#{month}-#{day}"
    end

    def format_time
      @params[:time] = time.gsub('hs', '').strip
    end

    def format_merchant
      @params[:merchant] = merchant
                           .strip # Quitar espacios al inicio y final
                           .gsub(/\s+/, ' ') # Reemplazar múltiples espacios por uno solo
    end

    def amount
      @params[:amount]
    end

    def merchant
      @params[:merchant]
    end

    def date
      @params[:date]
    end

    def time
      @params[:time]
    end

    def email_id
      @params[:email_id]
    end

    def transaction_date
      @params[:date]
    end

    def transaction_time
      @params[:time]
    end

    def summary_id
      @params[:summary_id]
    end
  end
end
