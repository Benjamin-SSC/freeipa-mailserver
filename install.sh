#!/bin/bash
cp plugin/ipaserver/plugins/mailserver.py /usr/lib/python3.9/site-packages/ipaserver/plugins/
cp plugin/schema.d/75-mailserver.ldif /usr/share/ipa/schema.d/
cp plugin/updates/75-mailserver.update /usr/share/ipa/updates/
mkdir -p /usr/share/ipa/ui/js/plugins/mailserver
cp plugin/ui/mailserver.js /usr/share/ipa/ui/js/plugins/mailserver/
/usr/sbin/ipa-server-upgrade

if [[ ! $? -eq 0 ]]; then
    echo "Something Went Wrong... exiting."
    exit 6
fi

SUFFIX=$(grep ^basedn /etc/ipa/default.conf | awk '{print $NF}')

echo "NOTE: Typed passwords will not print on screen!"

#read -sp "Enter the Admin user password you chose: " ADMINPASS
#echo

CONT=1
while [ -z "$POSTFIXPASS" ]; do
    read -sp "Choose a Password for the postfix ldap user: " password
    echo    # Move to the next line for cleaner output
    read -sp "Confirm password: " password_confirm
    echo    # Move to the next line for cleaner output

    if [ "$password" = "$password_confirm" ]; then
        # Proceed with actions requiring authentication
        POSTFIXPASS="$password"
    else
        echo "Passwords do not match. Please try again."
        # Handle password mismatch (e.g., exit or loop back for re-entry)
    fi
done


read -d '' ldif <<LDIF
dn: uid=postfix,cn=sysaccounts,cn=etc,${SUFFIX}
only:userPassword:${POSTFIXPASS}
LDIF

echo "Setting the postfix user password..."
printf '%s\n' "$ldif" | ipa-ldap-updater /dev/stdin

read -d '' ldif <<LDIF
dn: cn=System: Read Mail Server Postfix Configuration,cn=permissions,cn=pbac,${SUFFIX}
only:member:uid=postfix,cn=sysaccounts,cn=etc,${SUFFIX}
LDIF

echo "Adding postfix user to System: Read Mail Server Postfix Configuration permission..."
printf '%s\n' "$ldif" | ipa-ldap-updater /dev/stdin

echo "Now lets add a postfix mail transport"
while [ -z "$IMDONE" ]; do
    read -p "What email domain do you want to add? " DOMAIN
    echo "A transport line looks something like 'smtp:mailserver.example.com... read the postfix docs"
    read -p "What transport line do you want for ${DOMAIN}? " TRANSPORT

    echo "Adding \"${TRANSPORT}\" for domain \"${DOMAIN}\"..."

# CAN'T INDENT FOR REASONS
read -d '' ldif <<LDIF
dn: cn=${DOMAIN},cn=transports,cn=postfix,cn=mailserver,cn=etc,${SUFFIX}
add:objectclass:top
add:objectclass:nsContainer
add:objectclass:transportTable
add:cn:${DOMAIN}
only:transport:${TRANSPORT}
LDIF

    printf '%s\n' "$ldif" | ipa-ldap-updater /dev/stdin

    while true; do
        read -p "Do you want to add any more transports? (y/n)" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) IMDONE="IM_SO_DONE"; break;;
            * ) echo "Please answer y or n.";;
        esac
    done
done

echo "Use Apache Directory Studio for any more changes."
