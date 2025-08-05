#!/bin/sh

# Check if argon2 is installed
if command -v argon2 >/dev/null 2>&1; then
    ARGON_INSTALLED=true
else
    ARGON_INSTALLED=false
fi

# Check if Docker is installed
if command -v docker >/dev/null 2>&1; then
    DOCKER_INSTALLED=true
else
    DOCKER_INSTALLED=false
fi

# Function to generate a random password
generate_random_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()_+{}|:<>?=' < /dev/urandom | head -c 48
}

# Function to obtain and hash the password using argon2 with OWASP recommended settings
generate_hash_argon2(){
  ADMIN_PASSWORD=$(ask_for_password)
  echo -n "$ADMIN_PASSWORD" | argon2 "$(openssl rand -base64 32)" -e -id -k 19456 -t 2 -p 1
  echo "Password: $ADMIN_PASSWORD"
  echo "Hashed Password: $HASHED_PASSWORD"
}

# Function to use Docker for hashing
generate_hash_docker() {
    ADMIN_PASSWORD=$(generate_random_password)
    HASHED_PASSWORD=$(echo "$ADMIN_PASSWORD" | docker run --rm -i vaultwarden/server /vaultwarden hash --preset owasp 2>/dev/null)
    echo "$ADMIN_PASSWORD" "$HASHED_PASSWORD"

    echo "ADMIN_PASSWORD" | docker run --rm -i vaultwarden/server /vaultwarden hash --preset owasp 2>/dev/null

    ADMIN_PASSWORD=$(echo "$RESULT" | head -n 1)
    HASHED_PASSWORD=$(echo "$RESULT" | tail -n 1)
}

# Function to ask for password input
ask_for_password() {
    printf "Enter a password (minimum 12 characters) or leave blank to generate a random password: "
    # stty -echo
    read ADMIN_PASSWORD
    stty echo
    echo
    if [ -z "$ADMIN_PASSWORD" ]; then
        ADMIN_PASSWORD=$(generate_random_password)
    elif [ ${#ADMIN_PASSWORD} -lt 12 ]; then
        echo "Password must be at least 12 characters long. Please try again."
        ask_for_password
    fi
    echo "$ADMIN_PASSWORD"
}

# Main logic
if [ "$ARGON_INSTALLED" = true ]; then
    echo "Using argon2 package for hashing."
    generate_hash_argon2
elif [ "$DOCKER_INSTALLED" = true ]; then
    printf "Argon2 is not installed. Do you want to (i)nstall argon2 package, use (d)ocker, or (e)xit? "
    read CHOICE
    case "$CHOICE" in
        i)
            sudo apt-get update && sudo apt-get install -y argon2
            generate_hash_argon2
            ;;
        d)
            printf "Using Docker for hashing. Do you want to proceed? (y/n) "
            read PROCEED
            if [ "$PROCEED" = "y" ]; then
                RESULT=$(hash_password_docker)
                ADMIN_PASSWORD=$(echo "$RESULT" | head -n 1)
                HASHED_PASSWORD=$(echo "$RESULT" | tail -n 1)
                hash_password_docker
            else
                echo "Exiting."
                exit 1
            fi
            ;;
        e)
            echo "Exiting."
            exit 1
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac
else
    printf "Neither argon2 nor Docker is installed. It is recommended to install the argon2 package. Do you want to (i)nstall argon2 package or (e)xit? "
    read CHOICE
    case "$CHOICE" in
        i)
            sudo apt-get update && sudo apt-get install -y argon2
            generate_hash_argon2
            ;;
        e)
            echo "Exiting."
            exit 1
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac
fi

echo "Password: $ADMIN_PASSWORD"
echo "Hashed Password: $HASHED_PASSWORD"
