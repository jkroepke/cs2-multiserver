#! /bin/bash

# (C) 2016 Maximilian Wende <maximilian.wende@gmail.com>
#
# This file is licensed under the Apache License 2.0. For more information,
# see the LICENSE file or visit: http://www.apache.org/licenses/LICENSE-2.0




##################################### SETUP #####################################

setup () {
	# First-time setup
	cat <<-EOF
		-------------------------------------------------------------------------------
		                CS:GO Multi-Mode Server Manager - Initial Setup
		-------------------------------------------------------------------------------

		It seems like this is the first time you use this script on this machine.
		Before advancing, be aware of a few things:

		>>  A configuration file will be created in the location:
		        $(bold "$CFG")

		    If you want to use a different location, exit and edit
		    the \$MSM_CFG variable within this file accordingly.

		>>  For multi-user setups, this script, located at
		        $(bold "$THIS_SCRIPT")
		    must be readable for all users.

		EOF
	if ! prompt; then echo; return 1; fi

	# Query steam installation admin user
	cat <<-EOF

		Please choose the user that is responsible for the game installation and
		updates on this machine. As long as the access rights are correctly set,
		this server will use the game data provided by that user, which makes
		re-downloading the game for multiple users unnecessary.

		EOF

	while [[ ! $ADMIN_HOME ]]; do
		read -p "Admin's username (default: $USER) " -r ADMIN
		
		if [[ ! $ADMIN ]]; then ADMIN="$USER"; fi
		if [[ ! $(getent passwd $ADMIN) ]]; then
			caterr <<< "$(bold "ERROR:") User $(bold "$ADMIN") does not exist! Please specify a different admin."
			echo
			continue
			fi

		ADMIN_HOME=$(eval echo "~$ADMIN")
		if [[ ! -r $ADMIN_HOME ]]; then
			caterr <<-EOF
				$(bold "ERROR:") That user's home directory $(bold "$ADMIN_HOME")
				       is not readable! Please specify a different admin.

				EOF
			unset ADMIN_HOME; fi
		
		done

	echo
	# Check if the admin has a working configuration already
	if [[ $USER != $ADMIN ]]; then

		# If client installation fails (for instance, if the admin has no configuration himself)
		# try switching to the admin and performing the admin installation there
		if ! client-install; then
			catwarn <<-EOF
				$(bold "WARN:")  Additional installation steps are required on the account of $(bold "$ADMIN")!
				       Please log in to the account of $(bold "$ADMIN") now!
				EOF

			$SU $ADMIN -c "\"$THIS_SCRIPT\" admin-install"

			if (( $? )); then caterr <<-EOF
					$(bold "ERROR:") Admin Installation for $(bold "$ADMIN") failed!

					EOF
				return 1; fi

			# Try client installation again!
			if ! client-install; then caterr <<-EOF
					$(bold "ERROR:") Client Installation failed!

					EOF
				return 1; fi

			fi

	else
		admin-install
		fi
}

client-install () {
	echo "Trying to import settings from $(bold "$ADMIN") ..."

	ADMIN_HOME=$(eval echo "~$ADMIN")
	if [[ ! -r $ADMIN_HOME ]]; then caterr <<-EOF
			$(bold "ERROR:") The admin's home directory $(bold "$ADMIN_HOME") is not readable.

			EOF
		return 1; fi

	ADMIN_CFG="$(cfgfile $ADMIN_HOME)"
	readcfg "$ADMIN_CFG"
	if (( $? )); then echo; return 1; fi
	echo
	writecfg
	return 0
}

admin-install () {
	cat <<-EOF
		-------------------------------------------------------------------------------
		                  CS:GO Multi Server Manager - Admin Install
		-------------------------------------------------------------------------------

		Checking for an existing configuration ...
		EOF
	if readcfg 2> /dev/null; then
		if [[ $ADMIN == $USER ]]; then catwarn <<-EOF
				$(bold "WARN:")  A valid admin configuration already exists for this user $(bold "$ADMIN").
				       If you continue, the installation steps will be executed again.

				EOF
		else catwarn <<-EOF
				$(bold "WARN:")  This user is currently configured as client of user $(bold "$ADMIN").
				       If you continue, this user will create an own game installation instead.

				EOF
			fi
		if ! prompt; then echo; return 1; fi
		fi

	if [[ ! "$APPNAME" || ! "$APPID" ]]; then caterr <<-EOF
		$(bold "ERROR:") APPNAME and APPID are not set! Check this script and your
		       configuration file and try again!
		EOF
		return 1; fi

	echo
	ADMIN="$USER"
	ADMIN_HOME=~
	echo "You started the admin Installation for user $(bold "$ADMIN")"
	echo "This will create a configuration file in the location:"
	echo "        $(bold "$CFG")"
	echo
	if ! prompt; then echo; return 1; fi
	echo

	############ STEAMCMD ############
	# Check for an existing SteamCMD
	if [[ -x $ADMIN_HOME/steamcmd/steamcmd.sh ]]; then
		STEAMCMD_DIR="$ADMIN_HOME/steamcmd"
		catinfo <<< "$(bold "INFO:")  An existing SteamCMD was found in $(bold "$STEAMCMD_DIR")."
	else
		# Ask for the SteamCMD directory
		cat <<-EOF
			To download/update the game, installing SteamCMD is required. Be aware that
			this will use a lot of data! Please specify the place for SteamCMD to be
			installed in (absolute or relative to your home directory).

			EOF
		read -r -p "SteamCMD install directory (default: steamcmd) " STEAMCMD_DIR

		if [[ ! $STEAMCMD_DIR ]]; then
			STEAMCMD_DIR=steamcmd;
			fi
		if [[ ! $STEAMCMD_DIR =~ ^/ ]]; then
			STEAMCMD_DIR="$ADMIN_HOME/$STEAMCMD_DIR"
			fi
		# TODO: Add directory checks

		# Download and install SteamCMD
		WDIR=$(pwd)
		mkdir -p "$STEAMCMD_DIR"
		cd "$STEAMCMD_DIR"
		echo "Installing SteamCMD to $(bold $STEAMCMD_DIR) ..."

		unset SUCCESS
		until [[ $SUCCESS ]]; do
			wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
			if (( $? )); then
				caterr <<< "$(bold "ERROR:") SteamCMD Download failed."
				if ! prompt "Retry?"; then echo; return 1; fi
			else
				local SUCCESS=1
				fi
			done

		echo
		echo "Extracting ..."
		tar xzvf steamcmd_linux.tar.gz
		rm steamcmd_linux.tar.gz &> /dev/null
		if [[ ! -x $STEAMCMD_DIR/steamcmd.sh ]]; then
			caterr <<< "$(bold "ERROR:") SteamCMD installation failed."
			echo
			return 1; fi

		echo
		echo "Updating SteamCMD ..."
		echo "quit" | "$STEAMCMD_DIR/steamcmd.sh"
		echo
		echo "SteamCMD installed successfully."
		cd "$WDIR"
		fi

	############ GAME INSTALL DIRECTORY ############
	echo
	# check for an existing game installation
	if [[ $(cat "$ADMIN_HOME/$APPNAME/msm.d/appid" 2> /dev/null) == "$APPID" ]]; then
		INSTALL_DIR="$ADMIN_HOME/$APPNAME"
		catinfo <<< "$(bold "INFO:")  A previous game installation was found in $(bold "$INSTALL_DIR")."
	else
		echo "Next, please select the directory for the game server to be installed in."
		unset SUCCESS
		until [[ $SUCCESS ]]; do
			echo
			read -r -p "Game Server Installation Directory (default: $APPNAME) " INSTALL_DIR

			if [[ ! $INSTALL_DIR ]]; then 
				INSTALL_DIR="$APPNAME" 
				fi
			if [[ ! $INSTALL_DIR =~ ^/ ]]; then
				INSTALL_DIR="$ADMIN_HOME/$INSTALL_DIR"
				fi

			INSTANCE_DIR="$INSTALL_DIR" check-instance-dir

			errno=$?
			if (( $errno == 1 )); then
				catwarn <<-EOF
					Do you wish to create a base installation in $(bold "$INSTALL_DIR") anyway?

					EOF
				prompt && SUCCESS=1
			elif (( $errno )); then
				caterr <<-EOF
					$(bold "ERROR:") $(bold "$INSTALL_DIR") cannot be used as a base
					       installation directory!
					EOF
			else
				SUCCESS=1
				fi
			if [[ ! $SUCCESS ]]; then
				echo "Please specify a different directory."
				fi
		done
		mkdir -p "$INSTALL_DIR"
		fi

	echo
	echo "Preparing installation directories ..."

	INSTANCE_DIR="$INSTALL_DIR"

	# Create SteamCMD Scripts
	cat > "$STEAMCMD_DIR/update" <<-EOF
		login anonymous
		force_install_dir "$INSTALL_DIR" 
		app_update $APPID
		quit
		EOF

	cat > "$STEAMCMD_DIR/validate" <<-EOF
		login anonymous
		force_install_dir "$INSTALL_DIR" 
		app_update $APPID validate
		quit
		EOF

	cat > "$STEAMCMD_DIR/update-check" <<-EOF
		login anonymous
		app_info_update 1
		app_info_print 740
		quit
		EOF

	############ PREPARE MSM DIRECTORY ############

	# Create settings directory within INSTALL_DIR
	mkdir -p "$INSTALL_DIR/msm.d"

	echo "$APPID" > "$INSTALL_DIR/msm.d/appid"
	echo "$APPNAME" > "$INSTALL_DIR/msm.d/appname"
	if [[ ! -e "$INSTALL_DIR/msm.d/server.conf" ]]; then
		cp "$SUBSCRIPT_DIR/server.conf" "$INSTALL_DIR/msm.d/server.conf"
		fi
	touch "$INSTALL_DIR/msm.d/is-admin"

	fix-permissions

	# Create Config and make it readable
	echo
	writecfg
	chmod a+r "$CFG"

	cat <<-EOF
		Basic Setup Complete!

		Do you want to install/update the game right now? If you choose No, you can
		install the game later using '$THIS_COMM install' or copy the files manually.

		EOF

	if prompt "Install Now?"; then
		echo
		update
		return 0; fi

	echo
	return 0
}