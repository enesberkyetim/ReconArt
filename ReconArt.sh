#!/bin/bash

# --- CONFIGURATION ---
WORDLIST="$HOME/wordlists/all.txt"
PATTERN_MATCH_WORDLIST="$HOME/wordlists/hq_critical_subdomain_keywords.txt"
THREADS_ACTIVE=1000
THREADS_HTTPX=50
RATE_LIMIT_HTTPX=20
BOT_TOKEN="$TELEGRAM_API_TOKEN"
CHAT_ID="$TELEGRAM_CHAT_TOKEN"
GREEN='\033[0,32m'
RED='\033[0,31m'
YELLOW='\033[1,33m'
CYAN='\033[0,36m'
NC='\033[0m'
WHITE='\033[1;37m'

if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    echo -e "${RED}[!] Error: Telegram credentials not found in .bashrc!${NC}"
fi

banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
 8888888b.                                           d8888          888
 888   Y88b                                         d88888          888
 888    888                                        d88P888          888
 888   d88P .d88b.  .d8888b .d88b.  88888b.       d88P 888 888d888 888888
 8888888P" d8P  Y8b d88P"   d88""88b 888 "88b    d88P  888 888P"    888
 888 T88b  88888888 888     888  888 888  888   d88P   888 888      888
 888  T88b Y8b.     Y88b.   Y88..88P 888  888  d8888888888 888      Y88b.
 888   T88b "Y8888   "Y8888P "Y88P"  888  888 d88P     888 888       "Y888'
EOF
    echo -e "${NC}"
}

setup_folders() {
        apply_scope_filter
    echo -e "${YELLOW}[?] Identification Phase: Syncing targets...${NC}"
    read -p "Enter path to target file: " target_file

    if [[ ! -f "$target_file" ]]; then
        echo -e "${RED}[!] Error: File not found!${NC}"
        return
    fi

    echo -e "${CYAN}[*] Extracting unique root domains...${NC}"
    unique_roots=$(sed -E 's|https?://||; s|/.*||' "$target_file" | python3 -c "
import sys
import tldextract
domains = set()
for line in sys.stdin:
    ext = tldextract.extract(line.strip())
    if ext.domain and ext.suffix:
        domains.add(f'{ext.domain}.{ext.suffix}')
print('\n'.join(sorted(domains)))
")

    for root_domain in $unique_roots; do
        dir="roots/root_$root_domain"
        file="$dir/subdomains.txt"
        mkdir -p "$dir"

        old_count=$(if [[ -f "$file" ]]; then wc -l < "$file"; else echo 0; fi)
        grep "$root_domain" "$target_file" >> "$file"
        sort -u "$file" -o "$file"

        new_count=$(wc -l < "$file")
        added=$((new_count - old_count))

        if [[ $added -gt 0 ]]; then
            echo -e "${GREEN}[+] $root_domain: Added $added new subs (Total: $new_count)${NC}"
        fi
    done
    echo -e "${GREEN}[*] Sync completed.${NC}"
    sleep 2
}

update_resolvers() {
    echo -e "${CYAN}[*] Optimizing DNS resolvers...${NC}"
    curl -s https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt > resolvers.txt
}

run_subdomain_permutations() {
    for d in roots/*/; do
        target=$(basename "$d" | sed 's/root_//')
        master_list="${d}subdomains.txt"
        perm_output="${d}permutations_valid.tmp"

        if [[ ! -s "$master_list" ]]; then
            echo -e "${YELLOW}[!] $target için subdomain listesi boş, atlanıyor.${NC}"
            continue
        fi

        echo -e "${CYAN}[*] Generating permutations for: $target${NC}"
        
        # dnsgen ile permütasyon üret ve doğrudan shuffledns'e pasla (Hız için pipe kullanımı)
        # --fast bayrağı hız kazandırır, wordlist kullanıyorsan dnsgen'e -w ile verebilirsin
        cat "$master_list" | dnsgen - | \
        shuffledns -d "$target" -r resolvers.txt -t $THREADS_ACTIVE -m $(which massdns) -silent | \
        anew "$perm_output"

        if [ -s "$perm_output" ]; then
            new_count=$(wc -l < "$perm_output")
            echo -e "${GREEN}[+] Found $new_count new subdomains via permutations!${NC}"
            
            # Master listeyi güncelle
            cat "$perm_output" >> "$master_list"
            sort -u "$master_list" -o "$master_list"
            apply_scope_filter "$master_list"
            
            # Httpx ile servis kontrolü yap
            echo -e "${WHITE}[>] Probing new permutation results...${NC}"
            httpx -l "$perm_output" -td -sc -title -server -random-agent -rl $RATE_LIMIT_HTTPX -t $THREADS_HTTPX -silent -o "${d}httpx_live_permutations.txt"
            
            rm "$perm_output"
        else
            echo -e "${YELLOW}[-] No new subdomains found via permutations for $target.${NC}"
        fi
        analyze_results "$d"
    done
}

run_subdomain_enum_active() {
    if [[ ! -f "$WORDLIST" ]]; then
        echo -e "${RED}[!] Error: Wordlist not found at $WORDLIST${NC}"
        return
    fi

    update_resolvers

    for d in roots/*/; do
        target=$(basename "$d" | sed 's/root_//')

        #if [ -f "${d}active_results.txt" ]; then
            #echo -e "${YELLOW}[!] $target already brute-forced, skipping.${NC}"
            #continue
        #fi

        echo -e "${CYAN}[*] Scaling Active Recon: $target${NC}"

        if timeout 20m shuffledns -d "$target" -w "$WORDLIST" -r resolvers.txt -t $THREADS_ACTIVE -m $(which massdns) -silent -o "${d}active.tmp"; then
            if [ -s "${d}active.tmp" ]; then
                # comm komutu için dosyalar sıralanmalı
                sort -u "${d}active.tmp" -o "${d}active.tmp"
                sort -u "${d}subfinder_results.txt" -o "${d}subfinder_results.txt" 2>/dev/null

                # Sadece pasif taramada bulunmayanları ayıkla
                comm -23 "${d}active.tmp" "${d}subfinder_results.txt" > "${d}active_unique.txt" 2>/dev/null

                apply_scope_filter "${d}active_unique.txt"

                if [ -s "${d}active_unique.txt" ]; then
                    local ports="80,81,300,443,591,593,832,981,1010,1311,1099,2082,2095,2096,2480,3000,3128,3333,4243,4443,4444,4567,4711,4712,4993,5000,5104,5108,5280,5281,5601,5800,6543,7000,7001,7396,7474,8000,8001,8008,8014,8042,8060,8069,8080,8081,8083,8088,8090,8091,8095,8118,8123,8172,8181,8222,8243,8280,8281,8333,8337,8443,8444,8500,8800,8834,8880,8881,8888,8983,9000,9001,9043,9060,9080,9090,9091,9200,9443,9502,9800,9981,10000,10250,11371,12443,15672,16080,17778,18091,18092,20720,27201,32000,55440,55672"
                    echo -e "${GREEN}[+] Unique subdomains found! Probing...${NC}"
                    httpx -l "${d}active_unique.txt" -timeout 10 -max-time 20 -td -sc -title -server -random-agent -ports "$ports" -rl $RATE_LIMIT_HTTPX -t $THREADS_HTTPX -o "${d}httpx_live_active.txt" -silent
                    apply_scope_filter "${d}httpx_live_active.txt"

                    if [ -s "${d}active_unique.txt" ]; then
                        cat "${d}active_unique.txt" >> "${d}subdomains.txt"
                        sort -u "${d}subdomains.txt" -o "${d}subdomains.txt"
                        apply_scope_filter "${d}subdomains.txt"
                        echo -e "${GREEN}[+] Master list updated with active results.${NC}"
                    fi
                fi
                mv "${d}active.tmp" "${d}active_results.txt"
            else
                touch "${d}active_results.txt"
            fi
        fi
        analyze_results "$d"
    done
    
    echo -e "${GREEN}[*] Active enumeration finished.${NC}"
    sleep 2
}

run_subdomain_enum_passive() {
    for d in roots/*/; do
        target=$(basename "$d" | sed 's/root_//')

        #if [ -f "${d}httpx_live.txt" ]; then
            #echo -e "${YELLOW}[!] $target already fully scanned, skipping.${NC}"
            #continue
        #fi

        echo -e "${CYAN}[*] Processing: $target${NC}"

        if subfinder -dL "${d}subdomains.txt" -all -timeout 10 -max-time 25 -silent -o "${d}subfinder.tmp"; then
            if [ -s "${d}subfinder.tmp" ]; then
                echo -e "${WHITE}[>] Subfinder done, starting httpx...${NC}"
                if httpx -l "${d}subfinder.tmp" -td -sc -title -server -random-agent -rl $RATE_LIMIT_HTTPX -t $THREADS_HTTPX -silent -timeout 10 -o "${d}httpx.tmp"; then
                    mv "${d}httpx.tmp" "${d}httpx_live.txt"
                    apply_scope_filter "${d}httpx_live.txt"
                    mv "${d}subfinder.tmp" "${d}subfinder_results.txt"
                    apply_scope_filter "${d}subfinder_results.txt"
                    echo -e "${GREEN}[+] $target finished successfully.${NC}"

                    if [ -s "${d}subfinder_results.txt" ]; then
                        cat "${d}subfinder_results.txt" >> "${d}subdomains.txt"
                        sort -u "${d}subdomains.txt" -o "${d}subdomains.txt"
                        apply_scope_filter "${d}subdomains.txt"
                        echo -e "${GREEN}[+] Master list updated with passive results.${NC}"
                    fi
                else
                    rm -f "${d}httpx.tmp"
                fi
            else
                touch "${d}httpx_live.txt"
                rm -f "${d}subfinder.tmp"
            fi
        else
            rm -f "${d}subfinder.tmp"
        fi
        analyze_results "$d"
    done
    
}

recon_menu() {
    while true; do
        banner
        echo -e "${WHITE}1)${NC} Subdomain Enumeration (Passive)"
        echo -e "${WHITE}2)${NC} Subdomain Enumeration (Active/Brute)"
        echo -e "${WHITE}3)${NC} Clear Workspaces"
        echo -e "${WHITE}4)${NC} Back to Main Menu"
        echo "-----------------------------------------------"
        read -p "Selection [1-4]: " choice

        case $choice in
            1) run_subdomain_enum_passive ;;
            2) run_subdomain_enum_active ;;
            3) read -p "Delete all data in roots/? (y/N): " confirm
               [[ $confirm == [yY] ]] && rm -rf roots/* && echo "Cleared." || echo "Aborted." ; sleep 2 ;;
            4) return ;;
            *) echo -e "${RED}[!] Invalid selection!${NC}" ; sleep 2 ;;
        esac
    done
}

pre_recon() {
    echo -e "${YELLOW}[?] Intelligence Phase: Collecting root domains...${NC}"
    echo -e "${WHITE}1)${NC} Discover by Organization Name (Amass Intel)"
    echo -e "${WHITE}2)${NC} Discover by ASN (Amass Intel)"
    echo -e "${WHITE}3)${NC} Import Manual List"
    echo -e "${WHITE}4)${NC} Shodan SSL/Hostname Hunt (Multi)"
    echo -e "${WHITE}5)${NC} Shodan Org/Hostname Hunt (Multi)"
    echo -e "${WHITE}6)${NC} Shodan ASN/Hostname Hunt (Multi)"
    echo -e "${WHITE}7)${NC} Back to Main Menu"
    read -p "Selection [1-7]: " intel_choice

    case $intel_choice in
        1) read -p "Enter Organization Name: " org_name; amass intel -org "$org_name" | anew seeds.txt ;;
        2) read -p "Enter ASN: " asn_num; amass intel -asn "$asn_num" | anew seeds.txt ;;
        3) read -p "Enter path to manual list: " manual_path; [[ -f "$manual_path" ]] && cat "$manual_path" | sed -E 's|https?://||; s|/.*||' | grep -Eo '[a-zA-Z0-9-]+\.[a-z]+$' | anew seeds.txt ;;
        4|5|6)
            case $intel_choice in
                4) read -p "Enter SSL target(s) (comma separated): " targets; filter="ssl" ;;
                5) read -p "Enter Org target(s) (comma separated): " targets; filter="org" ;;
                6) read -p "Enter ASN target(s) (comma separated): " targets; filter="asn" ;;
            esac

            IFS=',' read -ra ADDR <<< "$targets"
            for t in "${ADDR[@]}"; do
                t=$(echo "$t" | xargs) # Boşlukları temizle
                echo -e "${CYAN}[*] Searching Shodan for $filter: $t...${NC}"

                # Shodan Arama + Gelişmiş Temizlik Hattı
                shodan search "$filter":"$t" --fields hostnames | \
                tr ";" "\n" | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
                sed 's/^\*\.//' | \
                grep -E '^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$' | \
                sort -u | \
                anew seeds.txt
            done
            ;;
        7) return ;;
    esac

    # Filtreleme işlemi
    apply_scope_filter
    echo -e "${GREEN}[*] Intelligence gathering & filtering completed.${NC}"
    sleep 2
}

send_telegram() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
         -d "chat_id=$CHAT_ID" \
         -d "text=$message" \
         -d "parse_mode=Markdown" > /dev/null
}

analyze_results() {
    local target_dir=${1:-"roots/*/"}
    report_file="priority_targets.txt"
    touch "$report_file"

    for d in $target_dir; do
        for live_file in "${d}httpx_live.txt" "${d}httpx_live_active.txt"; do
            if [[ -f "$live_file" ]]; then
                
                # ADIM 1: Önce canlı sonuçları scope listesine göre filtrele
                # Sadece in_scope.txt içindeki kalıplara uyanları tutar
                awk '$1!="" {print $1, $0}' "$live_file" | grep -iE -f in_scope.txt | cut -d' ' -f2- > "${live_file}.filtered"

                # ADIM 2: Eğer out_of_scope.txt varsa onları da temizle
                if [[ -f "out_of_scope.txt" ]]; then
                    awk '$1!="" {print $1, $0}' "${live_file}.filtered" | grep -viE -f out_of_scope.txt  | cut -d' ' -f2- > "${live_file}.final"
                else
                    mv "${live_file}.filtered" "${live_file}.final"
                fi

                # ADIM 3: Sadece filtrelenmiş sonuçlarda kritik kelimeleri ara
                grep -i -f "$PATTERN_MATCH_WORDLIST" "${live_file}.final" | while read -r line; do
                    if ! grep -q "$line" "$report_file"; then
                        echo "$line" >> "$report_file"
                        send_telegram "🚨 *VERIFIED IN-SCOPE CRITICAL:* %0A$line"
                        echo -e "${RED}[CRITICAL]${NC} $line"
                    fi
                done
                rm -f "${live_file}.filtered" "${live_file}.final" # Geçici dosyaları temizle
            fi
        done
    done
}

apply_scope_filter() {
    local target_file=${1:-"seeds.txt"}
    
    if [[ ! -f "in_scope.txt" ]]; then
        echo -e "${RED}[!] Warning: in_scope.txt not found. Filtering skipped!${NC}"
        return
    fi

    # 1. ADIM: Sadece In-Scope olanları tut
    awk '$1!="" {print $1, $0}' "$target_file" | grep -iE -f in_scope.txt | cut -d' ' -f2- > "${target_file}.filtered"

    # 2. ADIM: Out-of-Scope olanları temizle
    if [[ -f "out_of_scope.txt" ]]; then
        awk '$1!="" {print $1, $0}' "${target_file}.filtered" | grep -viE -f out_of_scope.txt | cut -d' ' -f2- > "$target_file"
    else
        mv "${target_file}.filtered" "$target_file"
    fi
    rm -f "${target_file}.filtered"
}

menu() {
    while true; do
        banner
        echo -e "${WHITE}0)${NC} Pre-Recon Intelligence"
        echo -e "${WHITE}1)${NC} Prepare & Sync Workspaces (Horizontal)"
        echo -e "${WHITE}2)${NC} Recon Engine (Vertical)"
        echo -e "${WHITE}3)${NC} Manual Review (Live Targets Summary)"
        echo -e "${WHITE}4)${NC} Exit Headquarters"
        echo "-----------------------------------------------"
        read -p "Selection [0-4]: " choice

        case $choice in
                0) pre_recon ;;
            1) setup_folders ;;
            2) recon_menu ;;
            3) banner
               echo -e "${CYAN}--- ALL LIVE TARGETS (Passive + Active) ---${NC}"
               find roots/ -name "httpx_live*.txt" -exec cat {} + | sort -u | less ;;
            4) echo -e "${YELLOW}Shutting down Headquarters...${NC}"; exit 0 ;;
            *) echo -e "${RED}[!] Invalid selection!${NC}" ; sleep 2 ;;
        esac
    done
}

menu
