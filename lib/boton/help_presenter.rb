# frozen_string_literal: true

module Boton
  class HelpPresenter
    # ANSI color codes
    RESET   = "\e[0m"
    BOLD    = "\e[1m"
    CYAN    = "\e[36m"
    YELLOW  = "\e[33m"
    GREEN   = "\e[32m"
    GRAY    = "\e[90m"

    # Display help message
    # @return [nil]
    def self.show
      puts <<~HELP

        #{BOLD}#{CYAN}Macro Email Transaction Parser#{RESET}

        #{BOLD}USO:#{RESET}
          boton [COMANDO] [ARGUMENTO]

        #{BOLD}COMANDOS:#{RESET}
           #{YELLOW}(sin comando)#{RESET}          Sincronizar transacciones de hoy desde Gmail
           #{YELLOW}ayer#{RESET}                   Sincronizar transacciones de ayer
           #{YELLOW}desde FECHA#{RESET}             Sincronizar desde fecha especifica hasta hoy
           #{YELLOW}FECHA#{RESET}                  Sincronizar transacciones de fecha especifica
           #{YELLOW}open FECHA#{RESET}             Abrir nuevo resumen (cierra anterior si existe)
           #{YELLOW}reversos [FECHA]#{RESET}       Buscar reversos de FECHA (hoy por defecto) y marcarlos en la DB
           #{YELLOW}list#{RESET}                   Mostrar transacciones del resumen actual
           #{YELLOW}list FECHA#{RESET}             Mostrar transacciones de FECHA en el resumen actual
           #{YELLOW}list PALABRA#{RESET}           Buscar PALABRA en el resumen actual
           #{YELLOW}all#{RESET}                    Mostrar todas las transacciones del historial
           #{YELLOW}all FECHA#{RESET}              Mostrar todas las transacciones de FECHA
           #{YELLOW}all PALABRA#{RESET}            Buscar PALABRA en todo el historial
           #{YELLOW}help#{RESET}                   Mostrar esta ayuda

        #{BOLD}OPCIONES:#{RESET}
           #{YELLOW}--local#{RESET}                No consultar Gmail: mostrar sólo lo registrado
                                  en la base local (comandos de sincronización)

        #{BOLD}FORMATO DE FECHA:#{RESET}
          #{GREEN}YYYY-MM-DD#{RESET} #{GRAY}(ejemplo: 2026-01-09)#{RESET}
          #{YELLOW}ayer#{RESET}          #{GRAY}(palabra clave para el día anterior)#{RESET}
          #{YELLOW}hoy#{RESET}           #{GRAY}(palabra clave para el día actual)#{RESET}

        #{BOLD}EJEMPLOS:#{RESET}
           #{GREEN}boton#{RESET}                    #{GRAY}# Sincronizar hoy#{RESET}
           #{GREEN}boton ayer#{RESET}               #{GRAY}# Sincronizar ayer#{RESET}
           #{GREEN}boton desde 2026-06-05#{RESET}    #{GRAY}# Sincronizar desde 05/06/2026 hasta hoy#{RESET}
           #{GREEN}boton desde ayer#{RESET}          #{GRAY}# Sincronizar desde ayer hasta hoy#{RESET}
           #{GREEN}boton 2026-01-09#{RESET}         #{GRAY}# Sincronizar fecha especifica#{RESET}
           #{GREEN}boton open 2026-05-01#{RESET}    #{GRAY}# Abrir resumen de mayo#{RESET}
           #{GREEN}boton reversos#{RESET}           #{GRAY}# Buscar reversos de hoy#{RESET}
           #{GREEN}boton reversos 2026-08-22#{RESET} #{GRAY}# Buscar reversos de esa fecha#{RESET}
           #{GREEN}boton list#{RESET}               #{GRAY}# Ver transacciones del resumen actual#{RESET}
           #{GREEN}boton list 2026-01-09#{RESET}    #{GRAY}# Ver transacciones de esa fecha en el resumen#{RESET}
           #{GREEN}boton list ayer#{RESET}          #{GRAY}# Ver transacciones de ayer en el resumen#{RESET}
           #{GREEN}boton list cabify#{RESET}         #{GRAY}# Buscar "cabify" en el resumen actual#{RESET}
           #{GREEN}boton all#{RESET}                #{GRAY}# Ver todas las transacciones#{RESET}
           #{GREEN}boton all 2026-05-23#{RESET}     #{GRAY}# Ver todas del 23/05/2026#{RESET}
           #{GREEN}boton all uber#{RESET}           #{GRAY}# Buscar "uber" en todo el historial#{RESET}
           #{GREEN}boton --local#{RESET}            #{GRAY}# Ver lo registrado hoy, sin consultar Gmail#{RESET}
           #{GREEN}boton desde ayer --local#{RESET}  #{GRAY}# Ver lo registrado desde ayer, sin Gmail#{RESET}

      HELP
    end
  end
end
