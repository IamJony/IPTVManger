#!/bin/bash
# ============================================================
# Script: iptv_manager.sh
# Descripción: CLI interactiva para descargar canales IPTV por país
# Autor: IamJony https://github.com/IamJony
# Repositorio: https://github.com/IamJony/iptv-tools
# Licencia: MIT
# ============================================================

# Colores para interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # Sin color

# URLs de API
CHANNELS_URL="https://iptv-org.github.io/api/channels.json"
STREAMS_URL="https://iptv-org.github.io/api/streams.json"

# Directorio de trabajo
WORK_DIR="./iptv_downloads"
mkdir -p "$WORK_DIR"

# Archivos temporales
TEMP_DIR=$(mktemp -d)
CHANNELS_FILE="$TEMP_DIR/channels.json"
STREAMS_FILE="$TEMP_DIR/streams.json"

# Variables globales para progreso
TOTAL_STREAMS=0
PROCESADOS=0
FUNCIONAN=0
FALLAN=0

# ============================================================
# FUNCIONES AUXILIARES
# ============================================================

mostrar_banner() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    ${WHITE}IPTV MANAGER${NC} - By ${PURPLE}IamJony${NC}                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    ${YELLOW}GitHub:${NC} https://github.com/IamJony/iptv-tools         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

mostrar_progreso() {
    # Calcular ancho de barra (40 caracteres)
    local bar_width=40
    local filled=$(( (PROCESADOS * bar_width) / TOTAL_STREAMS ))
    local empty=$(( bar_width - filled ))
    
    # Construir barra
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+=" "; done
    bar+="]"
    
    # Calcular porcentaje
    local porcentaje=$(( (PROCESADOS * 100) / TOTAL_STREAMS ))
    
    # Limpiar línea actual y mostrar progreso
    echo -ne "\r\033[K"  # Borrar línea
    echo -ne "${CYAN}${bar} ${WHITE}${porcentaje}%${NC} "
    echo -ne "${BLUE}[${PROCESADOS}/${TOTAL_STREAMS}]${NC} "
    echo -ne "${GREEN}OK ${FUNCIONAN}${NC} "
    echo -ne "${RED}FAIL ${FALLAN}${NC}"
}

seleccionar_paises() {
    echo -e "${BLUE}SELECCION DE PAISES${NC}"
    echo "============================================="
    echo -e "${YELLOW}Ingresa los codigos de pais (ISO 3166-1 alpha-2)${NC}"
    echo -e "Ejemplo: ${WHITE}CO${NC} (Colombia), ${WHITE}ES${NC} (Espana), ${WHITE}MX${NC} (Mexico)"
    echo -e "${CYAN}Para multiples paises, separalos con comas:${NC} ${WHITE}CO,ES,MX,AR${NC}"
    echo -e "${YELLOW}O escribe 'ALL' para descargar todos los paises${NC}"
    echo "============================================="
    read -p "Codigos de pais: " PAISES_INPUT
    
    # Limpiar entrada
    PAISES_INPUT=$(echo "$PAISES_INPUT" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
    
    if [[ "$PAISES_INPUT" == "ALL" ]]; then
        PAISES_SELECCIONADOS=("ALL")
        echo -e "${GREEN}Se descargaran todos los paises${NC}"
    else
        IFS=',' read -ra PAISES_SELECCIONADOS <<< "$PAISES_INPUT"
        echo -e "${GREEN}Paises seleccionados: ${WHITE}${PAISES_SELECCIONADOS[*]}${NC}"
    fi
    echo ""
}

preguntar_probar_streams() {
    echo -e "${BLUE}PRUEBA DE STREAMS${NC}"
    echo "============================================="
    echo -e "${YELLOW}Deseas probar los streams antes de generar la lista?${NC}"
    echo -e "${CYAN}Esto puede tomar varios minutos dependiendo de la cantidad${NC}"
    echo -e "${CYAN}de canales encontrados.${NC}"
    echo -e "  ${WHITE}1${NC}) Si, probar todos (recomendado)"
    echo -e "  ${WHITE}2${NC}) No, generar lista sin probar (mas rapido)"
    echo "============================================="
    read -p "Opcion [1-2]: " OPCION_PROBAR
    
    case $OPCION_PROBAR in
        1) PROBAR_STREAMS=true ;;
        2) PROBAR_STREAMS=false ;;
        *) PROBAR_STREAMS=true ;;
    esac
    echo ""
}

preguntar_formato() {
    echo -e "${BLUE}FORMATOS DE SALIDA${NC}"
    echo "============================================="
    echo -e "${CYAN}Que formatos deseas generar?${NC}"
    echo -e "  ${WHITE}1${NC}) Solo TXT (reporte)"
    echo -e "  ${WHITE}2${NC}) Solo M3U (lista para reproductores)"
    echo -e "  ${WHITE}3${NC}) Ambos (TXT + M3U)"
    echo "============================================="
    read -p "Opcion [1-3]: " OPCION_FORMATO
    
    case $OPCION_FORMATO in
        1) GENERAR_TXT=true; GENERAR_M3U=false ;;
        2) GENERAR_TXT=false; GENERAR_M3U=true ;;
        3) GENERAR_TXT=true; GENERAR_M3U=true ;;
        *) GENERAR_TXT=true; GENERAR_M3U=true ;;
    esac
    echo ""
}

# ============================================================
# FUNCIONES PRINCIPALES
# ============================================================

descargar_datos() {
    echo -e "${BLUE}Descargando datos de la API...${NC}"
    
    if ! curl -s -o "$CHANNELS_FILE" "$CHANNELS_URL"; then
        echo -e "${RED}Error al descargar canales${NC}"
        exit 1
    fi
    
    if ! curl -s -o "$STREAMS_FILE" "$STREAMS_URL"; then
        echo -e "${RED}Error al descargar streams${NC}"
        exit 1
    fi
    
    # Verificar que los archivos no estén vacíos
    if [ ! -s "$CHANNELS_FILE" ] || [ ! -s "$STREAMS_FILE" ]; then
        echo -e "${RED}Los archivos descargados estan vacios o corruptos${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Datos descargados correctamente${NC}"
    echo ""
}

procesar_paises() {
    echo -e "${BLUE}Procesando canales...${NC}"
    
    # Generar archivo de países según selección
    if [[ "${PAISES_SELECCIONADOS[0]}" == "ALL" ]]; then
        # Obtener todos los países únicos del archivo
        PAISES_DISPONIBLES=$(jq -r '.[].country | select(. != null and . != "")' "$CHANNELS_FILE" | sort -u)
        
        # Crear archivo temporal con todos los países
        echo "$PAISES_DISPONIBLES" > "$TEMP_DIR/paises.txt"
        echo -e "${GREEN}Se procesaran todos los paises disponibles${NC}"
    else
        # Usar los países seleccionados
        printf "%s\n" "${PAISES_SELECCIONADOS[@]}" > "$TEMP_DIR/paises.txt"
        echo -e "${GREEN}Se procesaran los paises seleccionados${NC}"
    fi
    
    # Contar cuántos países
    TOTAL_PAISES=$(wc -l < "$TEMP_DIR/paises.txt")
    echo -e "${CYAN}Total de paises a procesar: ${WHITE}$TOTAL_PAISES${NC}"
    echo ""
}

probar_stream() {
    local url=$1
    
    # Prueba rápida de HTTP
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    
    if [[ $http_code -ge 200 && $http_code -lt 400 ]]; then
        # Verificar tipo de contenido
        local content_type=$(curl -s -I --max-time 5 "$url" 2>/dev/null | grep -i "content-type" | awk '{print $2}' | tr -d '\r')
        
        if [[ "$content_type" == *"video"* ]] || [[ "$content_type" == *"mpeg"* ]] || [[ "$content_type" == *"m3u8"* ]]; then
            return 0  # Funciona
        else
            return 0  # Consideramos que funciona si responde
        fi
    else
        return 1  # No funciona
    fi
}

generar_listados() {
    local pais=$1
    local nombre_archivo=$(echo "$pais" | tr '[:upper:]' '[:lower:]')
    
    # Archivos de salida
    local txt_file="$WORK_DIR/${nombre_archivo}_reporte.txt"
    local m3u_file="$WORK_DIR/${nombre_archivo}_canales.m3u"
    
    echo -e "\n${CYAN}Generando listados para: ${WHITE}$pais${NC}"
    
    # 1. Obtener IDs de canales del país
    local ids_canales=$(jq -r --arg pais "$pais" '.[] | select(.country == $pais) | .id' "$CHANNELS_FILE")
    
    if [ -z "$ids_canales" ]; then
        echo -e "${YELLOW}No se encontraron canales para $pais${NC}"
        return
    fi
    
    # 2. Crear array de IDs
    local ids_array=$(echo "$ids_canales" | jq -R . | jq -s .)
    
    # 3. Obtener streams del país
    local streams_pais=$(jq --argjson ids "$ids_array" '
        .[] | 
        select(.channel as $c | $ids | index($c)) |
        {channel: .channel, url: .url, quality: .quality, audio_lang: .audio_lang}
    ' "$STREAMS_FILE")
    
    local total_streams=$(echo "$streams_pais" | jq -s 'length')
    
    if [ "$total_streams" -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron streams para $pais${NC}"
        return
    fi
    
    echo -e "${CYAN}Se encontraron ${WHITE}$total_streams${CYAN} streams para $pais${NC}"
    
    # 4. Inicializar archivos
    > "$txt_file"
    > "$m3u_file"
    
    # 5. Agregar header al M3U
    echo "#EXTM3U" >> "$m3u_file"
    echo "# Lista de canales de $pais" >> "$m3u_file"
    echo "# Generada por IamJony (https://github.com/IamJony)" >> "$m3u_file"
    echo "# Fecha: $(date)" >> "$m3u_file"
    echo "" >> "$m3u_file"
    
    # 6. Header del TXT
    echo "=============================================" > "$txt_file"
    echo "  REPORTE DE CANALES IPTV - $pais" >> "$txt_file"
    echo "  Generado por IamJony (https://github.com/IamJony)" >> "$txt_file"
    echo "  Fecha: $(date)" >> "$txt_file"
    echo "=============================================" >> "$txt_file"
    echo "" >> "$txt_file"
    
    # 7. Procesar cada stream con barra de progreso
    local total_funcionan=0
    local total_fallan=0
    
    # Guardar todos los streams en un array temporal para procesar
    local streams_array=()
    while IFS= read -r line; do
        streams_array+=("$line")
    done < <(echo "$streams_pais" | jq -c '.')
    
    TOTAL_STREAMS=${#streams_array[@]}
    PROCESADOS=0
    FUNCIONAN=0
    FALLAN=0
    
    echo -e "\n${CYAN}Probando streams...${NC}"
    
    # Procesar cada stream
    for stream in "${streams_array[@]}"; do
        local channel_id=$(echo "$stream" | jq -r '.channel // ""')
        local url=$(echo "$stream" | jq -r '.url // ""')
        local quality=$(echo "$stream" | jq -r '.quality // "No especificada"')
        local audio_lang=$(echo "$stream" | jq -r '.audio_lang // "No especificado"')
        
        # Obtener nombre del canal
        local nombre_canal=$(jq -r --arg id "$channel_id" '.[] | select(.id == $id) | .name' "$CHANNELS_FILE")
        if [ -z "$nombre_canal" ] || [ "$nombre_canal" = "null" ]; then
            nombre_canal="$channel_id"
        fi
        
        # Si está vacío, saltar
        if [ -z "$url" ] || [ "$url" = "null" ]; then
            continue
        fi
        
        # Probar el stream (si está habilitado)
        local estado="SIN PROBAR"
        if [ "$PROBAR_STREAMS" = true ]; then
            if probar_stream "$url"; then
                estado="FUNCIONA"
                ((FUNCIONAN++))
                ((total_funcionan++))
            else
                estado="FALLA"
                ((FALLAN++))
                ((total_fallan++))
            fi
        else
            estado="SIN PROBAR"
            ((FUNCIONAN++))
            ((total_funcionan++))
        fi
        
        # Actualizar contador
        ((PROCESADOS++))
        
        # Mostrar progreso (sin nombre del canal)
        mostrar_progreso
        
        # Guardar en TXT
        echo "Nombre: $nombre_canal" >> "$txt_file"
        echo "Calidad: $quality" >> "$txt_file"
        echo "Idioma: $audio_lang" >> "$txt_file"
        echo "URL: $url" >> "$txt_file"
        echo "Estado: $estado" >> "$txt_file"
        echo "---" >> "$txt_file"
        
        # Guardar en M3U (solo si funciona o si no se probó)
        if [ "$estado" != "FALLA" ]; then
            echo "#EXTINF:-1 tvg-id=\"$channel_id\" group-title=\"$pais\",$nombre_canal" >> "$m3u_file"
            echo "$url" >> "$m3u_file"
            echo "" >> "$m3u_file"
        fi
    done
    
    # Salto de línea después de la barra de progreso
    echo ""
    
    # 8. Agregar resumen al TXT
    echo "" >> "$txt_file"
    echo "=============================================" >> "$txt_file"
    echo "  RESUMEN" >> "$txt_file"
    echo "  Total de streams: $TOTAL_STREAMS" >> "$txt_file"
    echo "  Funcionan: $total_funcionan" >> "$txt_file"
    if [ "$PROBAR_STREAMS" = true ]; then
        echo "  Fallan: $total_fallan" >> "$txt_file"
    else
        echo "  (Sin prueba de streams)" >> "$txt_file"
    fi
    echo "=============================================" >> "$txt_file"
    
    # Mostrar resumen final
    echo -e "${GREEN}Generados:${NC}"
    echo -e "  TXT: ${WHITE}$txt_file${NC}"
    echo -e "  M3U: ${WHITE}$m3u_file${NC}"
    echo -e "${CYAN}  Resumen: ${WHITE}$total_funcionan/${TOTAL_STREAMS}${CYAN} canales funcionan${NC}"
    echo ""
}

# ============================================================
# EJECUCIÓN PRINCIPAL
# ============================================================

main() {
    mostrar_banner
    
    # Paso 1: Seleccionar países
    seleccionar_paises
    
    # Paso 2: Preguntar si probar streams
    preguntar_probar_streams
    
    # Paso 3: Preguntar formatos
    preguntar_formato
    
    # Paso 4: Descargar datos
    descargar_datos
    
    # Paso 5: Procesar países
    procesar_paises
    
    # Paso 6: Generar listados para cada país
    echo -e "${BLUE}Generando listados...${NC}"
    echo "============================================="
    
    while read -r pais; do
        if [ -n "$pais" ]; then
            generar_listados "$pais"
        fi
    done < "$TEMP_DIR/paises.txt"
    
    # Paso 7: Resumen final
    echo "============================================="
    echo -e "${GREEN}PROCESO COMPLETADO${NC}"
    echo -e "${CYAN}Todos los archivos guardados en: ${WHITE}$WORK_DIR${NC}"
    echo -e "${YELLOW}Puedes usar la lista M3U en VLC, Kodi, etc.${NC}"
    echo -e "${PURPLE}Repositorio: https://github.com/IamJony/iptv-tools${NC}"
    echo ""
    
    # Limpiar archivos temporales
    rm -rf "$TEMP_DIR"
}

# Manejar interrupción (Ctrl+C)
trap 'echo -e "\n${RED}Proceso interrumpido${NC}"; rm -rf "$TEMP_DIR"; exit 1' INT

# Ejecutar el programa
main