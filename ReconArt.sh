#!/bin/bash

# --- CONFIGURATION ---
WORDLIST="$HOME/wordlists/all.txt"
THREADS_ACTIVE=5000
THREADS_HTTPX=50
RATE_LIMIT_HTTPX=20

# --- COLOR DEFINITIONS ---
GREEN='\033[0,32m'
RED='\033[0,31m'
YELLOW='\033[1,33m'
CYAN='\033[0,36m'
NC='\033[0m'
WHITE='\033[1;37m'

banner() {
    clear
    echo -e "${CYAN}###############################################"
    echo -e "#         BUG BOUNTY HEADQUARTERS (HQ)        #"
    echo -e "#         Methodology: Jason Haddix v4        #"
    echo -e "###############################################${NC}"
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
    unique_roots=$(sed -E 's|https?://||; s|/.*||' "$target_file" | grep -Eo '[a-zA-Z0-9-]+\.[a-z]+$' | sort -u)

    for root_domain in $unique_roots; do
        dir="roots/root_$root_domain"
        file="$dir/subdomains.txt"
        mkdir -p "$dir"

        old_count=$(if [[ -f "$file" ]]; then wc -l < "$file"; else echo 0; fi)
        grep -w "$root_domain" "$target_file" >> "$file"
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

run_subdomain_enum_active() {
    if [[ ! -f "$WORDLIST" ]]; then
        echo -e "${RED}[!] Error: Wordlist not found at $WORDLIST${NC}"
        return
    fi

    update_resolvers

    for d in roots/*/; do
        target=$(basename "$d" | sed 's/root_//')

        if [ -f "${d}active_results.txt" ]; then
            echo -e "${YELLOW}[!] $target already brute-forced, skipping.${NC}"
            continue
        fi

        echo -e "${CYAN}[*] Scaling Active Recon: $target${NC}"

        if shuffledns -d "$target" -w "$WORDLIST" -r resolvers.txt -t $THREADS_ACTIVE -m $(which massdns) -silent -o "${d}active.tmp"; then
            if [ -s "${d}active.tmp" ]; then
                # comm komutu için dosyalar sıralanmalı
                sort -u "${d}active.tmp" -o "${d}active.tmp"
                sort -u "${d}subfinder_results.txt" -o "${d}subfinder_results.txt" 2>/dev/null

                # Sadece pasif taramada bulunmayanları ayıkla
                comm -23 "${d}active.tmp" "${d}subfinder_results.txt" > "${d}active_unique.txt" 2>/dev/null

                if [ -s "${d}active_unique.txt" ]; then
                    echo -e "${GREEN}[+] Unique subdomains found! Probing...${NC}"
                    httpx -l "${d}active_unique.txt" -td -sc -title -server -random-agent -rl $RATE_LIMIT_HTTPX -t $THREADS_HTTPX -o "${d}httpx_live_active.txt" -silent
                fi
                mv "${d}active.tmp" "${d}active_results.txt"
            else
                touch "${d}active_results.txt"
            fi
        fi
    done
    echo -e "${GREEN}[*] Active enumeration finished.${NC}"
    sleep 2
}

run_subdomain_enum_passive() {
    for d in roots/*/; do
        target=$(basename "$d" | sed 's/root_//')

        if [ -f "${d}httpx_live.txt" ]; then
            echo -e "${YELLOW}[!] $target already fully scanned, skipping.${NC}"
            continue
        fi

        echo -e "${CYAN}[*] Processing: $target${NC}"

        if timeout 15m subfinder -dL "${d}subdomains.txt" -all -silent -o "${d}subfinder.tmp"; then
            if [ -s "${d}subfinder.tmp" ]; then
                echo -e "${WHITE}[>] Subfinder done, starting httpx...${NC}"
                if httpx -l "${d}subfinder.tmp" -td -sc -title -server -random-agent -rl $RATE_LIMIT_HTTPX -t $THREADS_HTTPX -silent -timeout 10 -o "${d}httpx.tmp"; then
                    mv "${d}httpx.tmp" "${d}httpx_live.txt"
                    mv "${d}subfinder.tmp" "${d}subfinder_results.txt"
                    echo -e "${GREEN}[+] $target finished successfully.${NC}"
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
    echo -e "${WHITE}4)${NC} Shodan SSL/Hostname Hunt" # Yeni Seçenek
    echo -e "${WHITE}5)${NC} Shodan org/Hostname Hunt"
    echo -e "${WHITE}6)${NC} Shodan ASN/Hostname Hunt"
    echo -e "${WHITE}7)${NC} Back to Main Menu"
    read -p "Selection [1-7]: " intel_choice

    case $intel_choice in
        1)
            read -p "Enter Organization Name: " org_name
            amass intel -org "$org_name" | anew seeds.txt
            ;;
        2)
            read -p "Enter ASN: " asn_num
            amass intel -asn "$asn_num" | anew seeds.txt
            ;;
        3)
            read -p "Enter path to manual list: " manual_path
            [[ -f "$manual_path" ]] && cat "$manual_path" | sed -E 's|https?://||; s|/.*||' | grep -Eo '[a-zA-Z0-9-]+\.[a-z]+$' | anew seeds.txt
            ;;
        4)
            read -p "Enter SSL target (e.g., target.com): " shodan_target
            echo -e "${CYAN}[*] Searching Shodan for SSL: $shodan_target...${NC}"
            # Shodan hostnameleri çek, temizle ve seeds.txt'ye ekle
            shodan search ssl:"$shodan_target" --fields hostnames | \
    tr ";" "\n" | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    sed 's/^\*\.//' | \
    grep -E '^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$' | \
    sort -u | \
    anew seeds.txt
            ;;
        5) read -p "Enter org target (e.g., 'Vodafone Turkey'): " shodan_target
            echo -e "${CYAN}[*] Searching Shodan for org: $shodan_target...${NC}"
            # Shodan hostnameleri çek, temizle ve seeds.txt'ye ekle
            shodan search org:"$shodan_target" --fields hostnames | \
    tr ";" "\n" | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    sed 's/^\*\.//' | \
    grep -E '^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$' | \
    sort -u | \
    anew seeds.txt ;;
        6) read -p "Enter ASN target (e.g., 'AS123'): " shodan_target
            echo -e "${CYAN}[*] Searching Shodan for org: $shodan_target...${NC}"
            # Shodan hostnameleri çek, temizle ve seeds.txt'ye ekle
            shodan search asn:"$shodan_target" --fields hostnames | \
    tr ";" "\n" | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    sed 's/^\*\.//' | \
    grep -E '^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$' | \
    sort -u | \
    anew seeds.txt ;;
        7) return ;;
    esac

    # İstihbarat biter bitmez filtreyi uygula ki seeds.txt tertemiz kalsın
    apply_scope_filter
    echo -e "${GREEN}[*] Intelligence gathering & filtering completed.${NC}"
    sleep 2
}

apply_scope_filter() {
    # Dosyaların varlığını kontrol et
    if [[ ! -f "in_scope.txt" ]]; then
        echo -e "${RED}[!] Error: in_scope.txt not found. Cannot filter!${NC}"
        return
    fi

    echo -e "${YELLOW}[*] Applying scope filters to seeds.txt...${NC}"

    # 1. ADIM: Sadece In-Scope listesindeki kalıplara uyanları tut
    # -f: Dosyadan kalıpları oku, -i: Case-insensitive
    grep -i -f in_scope.txt seeds.txt > filtered_seeds.tmp

    # 2. ADIM: Eğer Out-of-Scope dosyası varsa, o kalıpları listeden SİL
    if [[ -f "out_of_scope.txt" ]]; then
        grep -vi -f out_of_scope.txt filtered_seeds.tmp > seeds.tmp
        mv seeds.tmp seeds.txt
    else
        mv filtered_seeds.tmp seeds.txt
    fi

    rm -f filtered_seeds.tmp
    echo -e "${GREEN}[+] Scope filtering completed. Active targets: $(wc -l < seeds.txt)${NC}"
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
