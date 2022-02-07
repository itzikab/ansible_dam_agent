#!/bin/sh

RA_KABI_NAME=kabi
KABI_FILE=${RA_KABI_NAME}.txt

RA_PKG_NAME=packages
PKG_FILE=${RA_PKG_NAME}.txt

OS_NAME_=""
OS_MAJOR_VER_=""
PROCESSOR_=""
KERNEL_=""
SP_=""

# This function finds the kernel range from the kabi file (used for UEK only)
# like test X -le Y, only where X and Y are kernel versions
kversion_le()
{
    X=$1
    Y=$2
    
    if [ $X = $Y ]; then
        return 0
    fi
    
    i=1
    for X_VAL in `echo $X | tr - ' '`; do # separate X to values by dashes, e.g. "2.6.5-0.31.0" -> "2.6.5 0.31.0" and iterate the result
        Y_VAL=`echo $Y | cut -d- -f${i}` # take the Y value respective to the current X value
        if [ $X_VAL != $Y_VAL ]; then
            j=1
            for X_VAL_FRAG in `echo $X_VAL | tr . ' '`; do # separate X_VAL to fragments by dots, e.g. "2.6.5" -> "2 6 5" and iterate the result
                Y_VAL_FRAG=`echo $Y_VAL | cut -d. -f${j}` # take the Y_VAL fragment respective to the current X_VAL fragemnt
                if [ -z "$Y_VAL_FRAG" ]; then # corner case: X_VAL has more dots than Y_VAL (e.g. x=2.6.16.60, y=2.6.16)
                    return 1
                fi
                if [ $X_VAL_FRAG != $Y_VAL_FRAG ]; then
                    if [ $X_VAL_FRAG -le $Y_VAL_FRAG ]; then
                        return 0
                    else
                        return 1
                    fi
                fi
                j=`expr $j + 1`
            done
            Y_VAL_FRAG=`echo $Y_VAL | cut -d. -f${j}` # corner case: Y_VAL has more dots than X_VAL. here, j is 1 more than the number of dots in X_VAL.
            if [ -n "$Y_VAL_FRAG" ]; then
                return 0
            fi
        fi
        i=`expr $i + 1`
    done
    return 0 # all X parts are equal to all Y parts
}

find_relevant_kernel_from_kabi()
{
	KERNEL_V=$1
	KERNEL_FLAVOR=$2
	
	cat ${KABI_FILE} | grep "^$KERNEL_FLAVOR" | {
	while read LINE; 
	do
		MIN_KERNEL_PATCH=`echo $LINE | awk '{ print $3 }'`
		MAX_KERNEL_PATCH=`echo $LINE | awk '{ print $4 }'`    
		if [ -z "$MIN_KERNEL_PATCH" -o -z "$MAX_KERNEL_PATCH" ]; then
			return 1
		fi
		
		if kversion_le "$MIN_KERNEL_PATCH" "$KERNEL_V" && kversion_le "$KERNEL_V" "$MAX_KERNEL_PATCH"; then
		    if [ $KERNEL_FLAVOR = TD ]; then
			    echo $LINE | awk '{ print $5 }'
	                return 0
		 elif [ "${KERNEL_FLAVOR}" = "UBN" ]; then
	            UBN_RELEASE=`echo $LINE | awk '{ print $5 }'`
		        lsb_release -r | grep $UBN_RELEASE >/dev/null # Verify that Ubuntu release is the same as shown in the kabi
            		if [ $? -eq 0 ]; then
                           echo $LINE | awk '{ print $1 }'
                           return 0
                    fi
		else # KERNEL_FLAVOR is UEK
			    OEL_DISTRO=`echo $LINE | awk '{ print $5 }'`
				uname -r | grep $OEL_DISTRO >/dev/null # Verify the OEL version is the same as shown in the kabi
				if [ $? -eq 0 ]; then
					echo $LINE | awk '{ print $6 }'
					return 0
				fi
			fi
		fi
	done
	return 2
	}
}

# For Linux only
get_linux_kernel_patch_level()
{
	SYS_KERNEL_CPUNUM=`cat /boot/config-$(uname -r) 2>/dev/null | grep -w CONFIG_NR_CPUS | sed 's:.*=::' | xargs`
    SYS_KERNEL_VERSION_STRING=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*\).*:\1:'`
    VER_A=`echo ${SYS_KERNEL_VERSION_STRING} | sed 's:\..*::'`
    VER_B=`echo ${SYS_KERNEL_VERSION_STRING} | sed 's:[0-9]\.*::' | sed 's:\..*::'`
    VER_C=`echo ${SYS_KERNEL_VERSION_STRING} | sed 's:[0-9]\.[0-9]*::' | sed 's:\.*::'`
    #KERNEL_PATCH_LEVEL=`($((${VER_A} << 16)) + $((${VER_B} << 8)) + ${VER_C})`
    KERNEL_PATCH_LEVEL=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*\).*:\1:' | sed 's:\.::g'`
    KERNEL_MAJOR_VER=`uname -r | sed 's:\([0-9]*.[0-9]*.\).*:\1:' | sed 's:\.::g'`
    KERNEL_PATCH_LEVEL_FULL_VERSION=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*\).*:\1:' | sed 's:\.::g' | sed 's:\-::g'`
    SMP_KERNEL=`uname -v | awk '{print $2}' | grep -i smp >& /dev/null && echo "true"`
    SMP_STRING=`[ "${SMP_KERNEL}" == "true" ] && echo "SMP"`
    #LINUX_26_CODE=132608
    #LINUX_2616_CODE=132624
    LINUX_26_CODE=26
    LINUX_2616_CODE=2616
    LINUX_2632_CODE=2632

    if [ "${SYS_PLATFORM}" == "i386" ]; then
        if [ "${KERNEL_MAJOR_VER}" -ge  "${LINUX_26_CODE}" ]; then
            # kernel 2.6.9 - hugemem kernel base symbol startes at 02XXXX
            IS_HUGE=`head -n 1 /proc/kallsyms|awk '{print $1}' | grep '^02' >& /dev/null && echo "true"`
            if [ "${IS_HUGE}" != "true" ]; then
                # kernel 2.6.16+ - check config file
                if [ "${KERNEL_PATCH_LEVEL}" -ge  "${LINUX_2616_CODE}" ]; then
					UNAMER=`uname -r`
                    IS_HUGE=`grep "CONFIG_X86_PAE=y" /boot/config-${UNAMER} >& /dev/null && echo "true"`
                fi
            fi
        else
            IS_HUGE=`head -n 1 /proc/ksyms | awk '{print $1}' | grep '^02' >& /dev/null && echo "true"`
            if [ "${IS_HUGE}" != "true" ]; then
                IS_HUGE=`grep "CONFIG_X86_4G=y" /boot/config-$(uname -r) >& /dev/null && echo "true"`
            fi
        fi
	fi

    # normally, we would test RHEL4 rather than kernel v2.6.9, however the latter has proved to be working for a long time and is threfore more trustworthy.
    if [ "${SYS_PLATFORM}" = "x86_64" ] && [ "${SMP_KERNEL}" = "true" ] && [ "${SYS_KERNEL_VERSION_STRING}" = 2.6.9 ] && [ -n "${SYS_KERNEL_CPUNUM}" ] && [ "${SYS_KERNEL_CPUNUM}" -gt 8 ]; then
        SMP_STRING="LARGESMP"
    fi 

    # The test will fail on 2.6.16+ when we have less the 4GB memory and the kernel name has no 'hugemem|pte'
    if [ "${IS_HUGE}" == "true" ]; then
        if [ "${KERNEL_PATCH_LEVEL}" -ge "${LINUX_2616_CODE}" ] && [ "${KERNEL_PATCH_LEVEL}" -lt "${LINUX_2632_CODE}" ]; then
            SMP_STRING="PAE"
        #In RHEL6 and above, the default kernel is PAE, but it is written as SMP in "uname -a"
        elif [ "${KERNEL_PATCH_LEVEL}" -ge "${LINUX_2632_CODE}" ]; then
            SMP_STRING="SMP"
        else
            SMP_STRING="HUGEMEM"
        fi
    fi

    # This tests for "bigsmp" kernel (variation of PAE, e.g. can be seen on SUSE kernels)
    uname -r 2>&1 | grep bigsmp > /dev/null && SMP_STRING="BIGSMP"
	
    SYS_KERNEL_PATCH_LEVEL=${KERNEL_PATCH_LEVEL}
    SYS_KERNEL_CONFIG=${SMP_STRING}${HUGEMEM_STRING}
    SYS_KERNEL_CONFIG=${SYS_KERNEL_CONFIG:-plain}
}

get_kernel_version()
{
    if [ $1 = UEK ]; then
		echo `uname -r | sed s/.el.*$//g`
    elif  [ $1 = TD ]; then	
	echo `uname -r | sed s/.TDC.*$//g`
     else #$1 = UBN
	    echo `uname -r | sed s/"-generic$"//g`
     fi
}

is_uek()
{
	WHICH_LSB_RELEASE_STR=`which lsb_release 2>/dev/null`
	if [ ! -z "${WHICH_LSB_RELEASE_STR}" ]; then	
		LSB_RELEASE_STR=`lsb_release -i | grep -i ubuntu` 
		if [ ! -z "${LSB_RELEASE_STR}" ]; then
			return 1
		fi
	fi
    LINUX_2632100_CODE=2632100
	LINUX_381316_CODE=381316
	KERENL_V_SUPPORT_UEK=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*\).*:\1:' | sed 's:\.::g' | sed 's:\-::g'`
    KERENL_V_CONTAIN_UEK=`uname -r | grep uek`
	IS_OO=`uname -r | awk -F '[-.]' '{print $4}' | rev | cut -c -2 | rev` > /dev/null 2>&1
	IS_NOT_0=`uname -r | awk -F '[-.]' '{print $4}' | rev | cut -c 3- | rev` > /dev/null 2>&1
    
    first_num=`echo $KERENL_V_SUPPORT_UEK | cut -b1`
    second_num=`echo $KERENL_V_SUPPORT_UEK | cut -b2`
    third_num=`echo $KERENL_V_SUPPORT_UEK | cut -b3`
    forth_num=`echo $KERENL_V_SUPPORT_UEK | cut -b4`
	fifth_num=`echo $KERENL_V_SUPPORT_UEK | cut -b5`
    
    EL=none
    uname -r | grep el5 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        EL=el5
    fi
	
	uname -r | grep el6 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        EL=el6
    fi

    uname -r | grep el7 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        EL=el7
    fi
	
	uname -r | grep el8 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        EL=el8
    fi
    
	rpm -q kernel-uek > /dev/null 2>&1 || rpm -q kernel-ueknano > /dev/null 2>&1 # UEK machine - has kernel-uek rpm or kernel-ueknano rpm installed and currently running kernel 2.6.32-100 and higher, and the last 3 digits in the kernel version is of type x00 (x!=0)
	if [ $? -eq 0 ]; then
	    if [ "${SYS_PLATFORM}" = "x86_64" ]; then
            if [ $first_num -eq 2 ] && [ $second_num -eq 6 ] && [ $third_num -eq 3 ] && [ $forth_num -eq 2 ] && [ "${IS_OO}" -eq "00" ] && [ "${IS_NOT_0}" -ne "0" ]; then
		        return 0
            elif [ $first_num -eq 2 ] && [ $second_num -eq 6 ] && [ $third_num -eq 3 ] && [ $forth_num -eq 9 ] && [ "${IS_OO}" -eq "00" ] && [ "${IS_NOT_0}" -ne "0" ]; then
                return 0
			elif [ ${EL} = el6 ]; then  # OEL6-UEK3/UEK4 validate that kernel version starts with 3.8.13/4.1.12 acoordingly, and uname contains the word 'uek'.
                if [ $first_num -eq 3 ] && [ $second_num -eq 8 ] && [ $third_num -eq 1 ] && [ $forth_num -eq 3 ] && [ ! -z $KERENL_V_CONTAIN_UEK ]; then
                    return 0
                elif [ $first_num -eq 4 ] && [ $second_num -eq 1 ] && [ $third_num -eq 1 ] && [ $forth_num -eq 2 ] && [ ! -z $KERENL_V_CONTAIN_UEK ]; then
                    return 0
                fi
            elif [ ${EL} = el7 ] || [ ${EL} = el8 ]; then  # OEL7-UEK3/UEK4/UEK5/UEK6 or OEL8-UEK6 validate that kernel version starts with 3.8.13/4.1.12/4.14.35/5.4.17-2011.2.2 acoordingly, and uname contains the word 'uek'.
                if [ $first_num -eq 3 ] && [ $second_num -eq 8 ] && [ $third_num -eq 1 ] && [ $forth_num -eq 3 ] && [ ! -z $KERENL_V_CONTAIN_UEK ]; then
                    return 0
                elif [ $first_num -eq 4 ] && [ $second_num -eq 1 ] && [ $third_num -eq 1 ] && [ $forth_num -eq 2 ] && [ ! -z $KERENL_V_CONTAIN_UEK ]; then
                    return 0
                elif [ $first_num -eq 4 ] && [ $second_num -eq 1 ] && [ $third_num -eq 4 ] && [ $forth_num -eq 3 ] && [ $fifth_num -eq 5 ] && [ ! -z $KERENL_V_CONTAIN_UEK ]; then
                    return 0
                elif [ $first_num -eq 5 ] && [ $second_num -eq 4 ] && [ $third_num -eq 1 ] && [ $forth_num -eq 7 ]  && [ ! -z $KERENL_V_CONTAIN_UEK ]; then
                    return 0
                fi
            fi
        fi
	fi
	
	# In OEL5, if the kernel patch level is 2.6.32-100 and the platform is x86_64, the machine UEK.
	if [ ${EL} = el5 ] && [ "${SYS_PLATFORM}" = "x86_64" ] && [ "${KERENL_V_SUPPORT_UEK}" -eq "${LINUX_2632100_CODE}" ]; then
	    return 0
    # OELx-UEK3 or higher -> validate that the uname contains the word 'uek'.
	elif [ "${SYS_PLATFORM}" = "x86_64" ] && [ "${KERENL_V_SUPPORT_UEK}" -ge "${LINUX_381316_CODE}" ] && [ ! -z ${KERENL_V_CONTAIN_UEK} ]; then
        return 0
    else # the machine is not UEK
	    return 1
	fi
}

is_xen()
{
    uname -r | grep xen > /dev/null 2>&1
}

is_suse()
{
	if [ -f /etc/SuSE-release ]; then
		SYS_DISTRO_VERSION=`grep VERSION /etc/SuSE-release | awk '{ print $3 }'`
		SYS_DISTRO_SP=`grep PATCHLEVEL /etc/SuSE-release | awk '{ print $3 }'`
		if [ -z "${SYS_DISTRO_SP}" ]; then
			SYS_DISTRO_SP=0
		fi
        
        # Handle cases in which SUSE 11 is represented as SP3, while it is actually SP2
        # Relevant for kernels which start with: 3.0.80-0.5, 3.0.80-0.7, 3.0.93-0.5, 3.0.101-0.5, 3.0.101-0.7
        # Taken from https://wiki.novell.com/index.php/Kernel_versions
        if [ $SYS_DISTRO_VERSION = 11 ] && [ $SYS_DISTRO_SP = 3 ]; then
            SUSE_KERNEL_VERSION_DIGIT_1=`uname -r | awk -F "[.-]" '{print $1}'`
            SUSE_KERNEL_VERSION_DIGIT_2=`uname -r | awk -F "[.-]" '{print $2}'`
            SUSE_KERNEL_VERSION_DIGIT_3=`uname -r | awk -F "[.-]" '{print $3}'`
            SUSE_KERNEL_VERSION_DIGIT_4=`uname -r | awk -F "[.-]" '{print $4}'`
            SUSE_KERNEL_VERSION_DIGIT_5=`uname -r | awk -F "[.-]" '{print $5}'`
            if [ $SUSE_KERNEL_VERSION_DIGIT_1 = 3 ] && [ $SUSE_KERNEL_VERSION_DIGIT_2 = 0 ] && [ $SUSE_KERNEL_VERSION_DIGIT_4 = 0 ]; then
                if [ $SUSE_KERNEL_VERSION_DIGIT_3 = 80 ] || [ $SUSE_KERNEL_VERSION_DIGIT_3 = 101 ]; then
                    if [ $SUSE_KERNEL_VERSION_DIGIT_5 = 5 ] || [ $SUSE_KERNEL_VERSION_DIGIT_5 = 7 ]; then
                        SYS_DISTRO_SP=2
                    fi
                elif [ $SUSE_KERNEL_VERSION_DIGIT_3 = 93 ]; then
                    if [ $SUSE_KERNEL_VERSION_DIGIT_5 = 5 ]; then
                        SYS_DISTRO_SP=2
                    fi
                fi
            fi
        fi
		return 0
	elif [ -f /etc/os-release ]; then # Suse 15 and above removed /etc/SuSE-release and use /etc/os-release
	    cat /etc/os-release | grep -i SLES > /dev/null 2>&1
		if [ $? -eq 0 ]; then # We must make sure that it is SLES
		    SYS_DISTRO_VERSION=`cat /etc/os-release | grep VERSION_ID | sed 's/VERSION_ID=//;s/\"//g' | cut -d. -f1`
			SYS_DISTRO_SP=`cat /etc/os-release | grep VERSION_ID | sed 's/VERSION_ID=//;s/\"//g' | cut -d. -s -f2`	
			if [ -z "${SYS_DISTRO_SP}" ]; then
				SYS_DISTRO_SP=0
			fi	
			return 0
		else
		    return 1
		fi
	else
		return 1
	fi
}

is_td()
{
    is_suse
	if [ $? -eq 0 ]; then
	    uname -r | grep TDC >/dev/null 2>&1
		if [ $? -eq 0 ]; then
		    return 0
		else
		    return 1
	    fi
    else
        return 1		
	fi
}

is_rhel()
{
    IS_CENTOS=no
    # First of all check if lsb_release command available and grab the major and minor version of the OS
    command -v lsb_release >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        # Check that the machine is a valid RHEL, and only after that grab the OS information
        IS_RHEL_MACHINE=`lsb_release -a | grep "Description" | awk -F " " '{print $2$3$4$5}'`
        CENTOS_OR_RHEL=`lsb_release -a | grep "Description" | awk -F " " '{print $2}'`
        if [ "${CENTOS_OR_RHEL}" = "CentOS" ]; then
            IS_CENTOS=yes
        fi
        
        if [ $ALLOW_CENTOS = yes ]; then
            IS_RHEL_MACHINE=RedHatEnterpriseLinux
        fi
        if [ "${IS_RHEL_MACHINE}" = "RedHatEnterpriseLinux" ]; then
            SYS_DISTRO_VERSION=`lsb_release -a | grep Release | awk '{print $2}' | grep -o "[0-9]" | head -n 1`
            SYS_DISTRO_MINOR_VERSION=`lsb_release -a | grep Release | awk '{print $2}' | grep -o "[0-9]" | tail -n 1`
        fi
    fi
    
    # In case the output of lsb_release was empty, take the output from /etc/redhat-release
    if [ -z $SYS_DISTRO_VERSION ] && [ -f /etc/redhat-release ]; then
        # Check that the machine is a valid RHEL, and only after that grab the OS information       
        IS_RHEL_MACHINE=`cat /etc/redhat-release | awk -F " " '{print $1$2$3$4}'`
        CENTOS_OR_RHEL=`cat /etc/redhat-release | awk -F " " '{print $1}'`
        if [ "${CENTOS_OR_RHEL}" = "CentOS" ]; then
            IS_CENTOS=yes
        fi
        if [ $ALLOW_CENTOS = yes ]; then
            IS_RHEL_MACHINE=RedHatEnterpriseLinux
        fi
        if [ "${IS_RHEL_MACHINE}" = "RedHatEnterpriseLinux" ]; then
		    SYS_DISTRO_VERSION=`grep -o "[0-9]" /etc/redhat-release | head -n 1`
            SYS_DISTRO_MINOR_VERSION=`grep -o "[0-9]" /etc/redhat-release | tail -n 1`
            if [ -z "${SYS_DISTRO_MINOR_VERSION}" ]; then
                SYS_DISTRO_MINOR_VERSION=0
            fi
        fi
	fi
    
    if [ -z "$SYS_DISTRO_VERSION" ]; then
        return 1
    else
        return 0
    fi
}


is_ubuntu()
{
    WHICH_LSB_RELEASE_STR=`which lsb_release 2>/dev/null`
    if [ ! -z "${WHICH_LSB_RELEASE_STR}" ]; then
        LSB_RELEASE_STR=`lsb_release -i | grep -i ubuntu`
        if [ ! -z "${LSB_RELEASE_STR}" ]; then
            SYS_DISTRO_VERSION=`cat /etc/os-release | grep VERSION_ID | sed 's/VERSION_ID=//;s/\"//g' | cut -d. -f1`
	        SYS_DISTRO_SP=`cat /etc/os-release | grep VERSION_ID | sed 's/VERSION_ID=//;s/\"//g' | cut -d. -f2`
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}


get_linux_rhel_6_KABI ()
{
    # Find the relevant RHEL6 Kernel ABI
    SYS_KERNEL_VERSION=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*\).*:\1:' | sed 's:\.::g'`
	LINUX_2632_CODE=2632
    if [ "${SYS_KERNEL_VERSION}" -eq "${LINUX_2632_CODE}" ]; then
	    RHEL_6K1_CODE=2632431
		RHEL_6_KABI_V=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*\).*:\1:' | sed 's:\.::g' | sed 's:\-::g'`
		RHEL_6K0_DISTRO_VER=6K0
		RHEL_6K1_DISTRO_VER=6K1
		
		if [ $RHEL_6_KABI_V -ge $RHEL_6K1_CODE ]; then # if Kernel ABI >= 2632431 (rhel6 update 5)
		    SYS_DISTRO_VERSION=${RHEL_6K1_DISTRO_VER}
		else # if Kernel ABI < 2632431
		    SYS_DISTRO_VERSION=${RHEL_6K0_DISTRO_VER}
		fi
    fi
	return 0
}

get_sys_os()
{
    SYS_OS=`uname -s | sed 's:[^A-Za-z0-9]*::g'`
	if [ -z "${SYS_OS}" ]; then
	    echo "Could not retrieve OS information."
		if [ $GET_OS_DETAILS = true ]; then
	        exit 1
		else
		    out 1
		fi
    else
	    if [ "${SYS_OS}" != AIX ]; then
		    SYS_PLATFORM=`uname -i`
		    if [ -z "${SYS_PLATFORM}" ]; then
			    echo "Could not retrieve OS information."
				if [ $GET_OS_DETAILS = true ]; then
			        exit 1
				else
				    out 1
		        fi
		    fi
	    fi
	fi
}

init_linux_vars_from_kabi()
{
    KERNEL_V=`get_kernel_version $1`
	KERNEL_FLAVOR_V=`find_relevant_kernel_from_kabi ${KERNEL_V} $1`
	RC=$?
	if [ $RC -ne 0 ]; then
		if [ $RC -eq 1 ]; then
			echo "kabi.txt text file is corrupted."
		elif [ $RC -eq 2 ]; then
			echo "Could not find relevant package for $1 $KERNEL_V"
		fi
		if [ $GET_OS_DETAILS = true ]; then
		    exit 1
		else
		    out 1
		fi
	fi
}

check_solaris_11_1_patch ()
{
    # Minimal Solaris 11.1 branch level is: 0.175.1.15.0.4.0
    solaris_11_1_branch=`pkg info entire | grep Branch | awk -F":  " '{print $2}' | sed 's/ //g'`
	# Remove spaces if there are any
    # We will check only the first 4 numbers, becasue there is no need to be more specific
    first_num=`echo $solaris_11_1_branch | cut -d . -f1`
    second_num=`echo $solaris_11_1_branch | cut -d . -f2`
    third_num=`echo $solaris_11_1_branch | cut -d . -f3`
    forth_num=`echo $solaris_11_1_branch | cut -d . -f4`
    
    if [ $first_num -ge 1 ]; then
        return 0
    fi
    
	RC=0
    if [ $second_num -lt 175 ]; then
        RC=1
    fi
	
	if [ $second_num -eq 175 ] && [ $third_num -lt 1 ]; then
	    RC=1
	fi
	
	if [ $second_num -eq 175 ] && [ $third_num -eq 1 ] && [ $forth_num -lt 15 ]; then
        RC=1
    fi
	
	if [ $RC = 1 ]; then
        return 1
	else
	    return 0
	fi
}

check_suse11sp4_kernel_meltdown_v13 ()
{
    KERNEL_VERSION_FIVE_PARTS_MAXIMUM=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*.[0-9]*\).*:\1:' | sed 's:\.: :g' | sed 's:\-: :g'`
	OS_NORMALIZED_KERNEL_V=`printf "%03d%03d%03d%03d%03d\n" $(echo $KERNEL_VERSION_FIVE_PARTS_MAXIMUM)`  
	MELTDOWN_NORMALIZED_KERNEL_V=`printf "%03d%03d%03d%03d%03d\n" $(echo 3.0.101-108.35 | tr '.-' ' ')`
	if [ $OS_NORMALIZED_KERNEL_V -ge $MELTDOWN_NORMALIZED_KERNEL_V ]; then
	    SYS_KERNEL_CONFIG=dummy
	fi
}

check_uek4_kernel_meltdown_v13 ()
{
    KERNEL_VERSION_FIVE_PARTS_MAXIMUM=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*.[0-9]*\).*:\1:' | sed 's:\.: :g' | sed 's:\-: :g'`
    OS_NORMALIZED_KERNEL_V=`printf "%03d%03d%03d%03d%03d\n" $(echo $KERNEL_VERSION_FIVE_PARTS_MAXIMUM)`
	MELTDOWN_NORMALIZED_KERNEL_V=`printf "%03d%03d%03d%03d%03d\n" $(echo 4.1.12-112.16 | tr '.-' ' ')`
	if [ $OS_NORMALIZED_KERNEL_V -ge $MELTDOWN_NORMALIZED_KERNEL_V ]; then
	    SYS_KERNEL=null
	fi
}

check_rhel6_kernel_meltdown_v13 ()
{
    KERNEL_VERSION_FIVE_PARTS_MAXIMUM=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*.[0-9]*\).*:\1:' | sed 's:\.: :g' | sed 's:\-: :g'`
    OS_NORMALIZED_KERNEL_V=`printf "%03d%03d%03d%03d%03d\n" $(echo $KERNEL_VERSION_FIVE_PARTS_MAXIMUM)`
	MELTDOWN_NORMALIZED_KERNEL_V=`printf "%03d%03d%03d%03d%03d\n" $(echo 2.6.32-431.87 | tr '.-' ' ')`
	if [ $OS_NORMALIZED_KERNEL_V -ge $MELTDOWN_NORMALIZED_KERNEL_V ]; then
	    SYS_DISTRO_VERSION=dummy
	fi
}

init_linux_rhel_xen_vars()
{
    get_linux_kernel_patch_level
    SYS_OS=RHEL
	SYS_KERNEL=XEN
}

init_linux_suse_xen_vars()
{
    get_linux_kernel_patch_level
    SYS_OS=SLE
	SYS_KERNEL=XEN
}

init_linux_uek_vars()
{
    PACKAGE_VERSION=$1
    is_rhel
	init_linux_vars_from_kabi UEK
	SYS_OS=OEL
	SYS_KERNEL=${KERNEL_FLAVOR_V}
    
    ### Recommend package installation on ueknano kernel only on UEK4 and UEK5
    rpm -q kernel-ueknano >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        if [ "${KERNEL_FLAVOR_V}" != "UEK-v4" ] && [ "${KERNEL_FLAVOR_V}" != "UEK-v5" ]; then
            SYS_KERNEL=null
        fi
    fi
}

init_linux_suse_vars()
{
    PACKAGE_VERSION=$1
    get_linux_kernel_patch_level
	SYS_OS=SLE
	SYS_KERNEL=${SYS_KERNEL_CONFIG}
}

init_linux_td_vars()
{
    PACKAGE_VERSION=$1
	FIRST_PART_OF_PKG_VER=`echo $PACKAGE_VERSION | cut -d. -f1`
	if [ $FIRST_PART_OF_PKG_VER -lt 14 ]; then
        init_linux_vars_from_kabi TD
	fi
	SYS_OS=TD-SLE
	SYS_KERNEL=${KERNEL_FLAVOR_V}
}

init_linux_ubuntu_vars()
{
    if [ "$SYS_DISTRO_VERSION" -eq 14 ]; then
        init_linux_vars_from_kabi UBN 
	fi
    SYS_OS=UBN
    SYS_KERNEL=SMP
}

init_linux_rhel_vars()
{
    PACKAGE_VERSION=$1
	get_linux_kernel_patch_level
	
	# We support RHEL 6 K0/K1 in 9.5.0 and 11.0.1 and not 6 like in newer versions
    if [ ${SYS_DISTRO_VERSION} = 6 ]; then
	    if [ "${PACKAGE_VERSION}" = "9.5.0" ]; then
	        get_linux_rhel_6_KABI
	    fi
    fi
	SYS_OS=RHEL
	SYS_KERNEL=${SMP_STRING}
    
    # RHEL 7.4 has a kernel issue, and we should block recommendation for versions 10.0 and 10.5
    FIRST_PART_OF_PKG_VER=`echo $PACKAGE_VERSION | cut -d. -f1`
    if [ "${KERNEL_PATCH_LEVEL_FULL_VERSION}" -ge "3100693" ]; then
        if [ ${FIRST_PART_OF_PKG_VER} -eq 10 ]; then
            SYS_DISTRO_VERSION=dummy
        fi
    fi
    
    # Do not allow CentOS recommendation for Centos 4
    if [ $IS_CENTOS = yes ] && [ ${SYS_DISTRO_VERSION} = 4 ]; then
        SYS_DISTRO_VERSION=dummy
    fi
	
	if [ `uname -r | grep \.elrepo\.` ]; then
	    SYS_DISTRO_VERSION=dummy
    fi
}

init_sunos_vars()
{
    PACKAGE_VERSION=$1
	
	SOLARIS_MAJOR_VERSION=`uname -v | cut -d. -f1`
	SOLARIS_MINOR_VERSION=`uname -v | cut -d. -f2`
	SOLARIS_11_4_AND_ABOVE=no
	
	if [ $SOLARIS_MAJOR_VERSION -lt 11 ]; then
	    SOLARIS_COMMAND_TO_USE=isalist
	else
	    if [ $SOLARIS_MAJOR_VERSION -eq 11 ]; then
		    if [ $SOLARIS_MINOR_VERSION -lt 4 ]; then
			    SOLARIS_COMMAND_TO_USE=isalist
			else
			    SOLARIS_COMMAND_TO_USE=isainfo
				SOLARIS_11_4_AND_ABOVE=yes
			fi
		else
		    SOLARIS_COMMAND_TO_USE=isainfo
			SOLARIS_11_4_AND_ABOVE=yes
		fi
	fi
	
	if [ "${SYS_PLATFORM}" = "i86pc" ]; then # Solaris x86
		if [ "${SOLARIS_COMMAND_TO_USE}" = "isalist" ]; then
		    SOLARIS_PROCESSOR=`isalist | sed 's: .*::' | xargs`
		else
		    SOLARIS_PROCESSOR=`isainfo -n`
		fi
		
		if [ "${SOLARIS_PROCESSOR}" = "amd64" ]; then
			SYS_PLATFORM=x86_64
		else
			SYS_PLATFORM=x86
		fi
	else # Solaris Sparc
		SYS_PLATFORM=`isainfo -n`
	fi
	SYS_DISTRO_VERSION=`uname -r`
    
    if [ "`uname -v | cut -d. -f1-2`" = "11.1" ]; then
        check_solaris_11_1_patch
		if [ $? -eq 1 ]; then
            SYS_DISTRO_VERSION=dummy_sol_11_1
        fi
	elif [ "${SOLARIS_11_4_AND_ABOVE}" = "yes" ]; then # We support Solaris 11.4 starting from v13.5 P20
	    FIRST_PART_OF_PKG_VER=`echo $PACKAGE_VERSION | cut -d. -f1`
        if [ ${FIRST_PART_OF_PKG_VER} -lt 13 ]; then
            SYS_DISTRO_VERSION=dummy
		fi
    fi
}

init_hpux_vars()
{
    SYS_PLATFORM=`uname -m`
	if [ "${SYS_PLATFORM}" != "ia64" ]; then
		SYS_PLATFORM=hppa
	fi
	SYS_DISTRO_VERSION=`uname -r | awk -F. '{print $2"."$3}'`
}

init_aix_vars()
{
    SYS_V=`uname -v`
	SYS_R=`uname -r`
	SYS_DISTRO_VERSION=${SYS_V}${SYS_R}
	SYS_P=`uname -p`
	SYS_B=`bootinfo -K`
	SYS_PLATFORM=${SYS_P}${SYS_B}  
}

GET_OS_DETAILS=false

init_get_os_details_vars()
{
    GET_OS_DETAILS=true
    KABI_FILE="${AGENT_HOME}"/bin/kernel/kabi.txt
	get_sys_os
	if  [ "${SYS_OS}" = "Linux" ]; then
        if is_xen; then
		    if is_rhel; then
		        init_linux_rhel_xen_vars
		    elif is_suse; then
			    init_linux_suse_xen_vars
			fi
		elif is_uek; then
		    init_linux_uek_vars
		elif is_td; then
            init_linux_td_vars
		elif is_suse; then
		    init_linux_suse_vars
		elif is_rhel; then
		    init_linux_rhel_vars
        elif is_ubuntu; then
            init_linux_ubuntu_vars 
		else
		    echo "Unsupported Linux distribution"
		    exit 1
		fi
    elif [ "${SYS_OS}" = "SunOS" ]; then
		init_sunos_vars
    elif [ "${SYS_OS}" = "HPUX" ]; then
		init_hpux_vars
    elif [ "${SYS_OS}" = "AIX" ]; then
		init_aix_vars
	else
	    echo "Unsupported OS"
	    exit 1
	fi
	
	OS_NAME_=${SYS_OS}
	OS_MAJOR_VER_=`echo ${SYS_DISTRO_VERSION}`
	PROCESSOR_=${SYS_PLATFORM}
	KERNEL_=${SYS_KERNEL}
	SP_=${SYS_DISTRO_SP}
	if [ "${OS_NAME_}" = "SLE" ] && [ ${OS_MAJOR_VER_} = 15 ]; then
        SP_=
    elif [ "${OS_NAME_}" = "SLE" ] && [ ${OS_MAJOR_VER_} = 12 ]; then
	    FIRST_PART_OF_PKG_VER=`echo $PACKAGE_VERSION | cut -d. -f1`
		if [ ${FIRST_PART_OF_PKG_VER} -ge 14 ]; then
	        SP_=
		else
		    SP_=${SYS_DISTRO_SP}
		fi
	elif [ "${OS_NAME_}" = "TD-SLE" ]; then
	    FIRST_PART_OF_PKG_VER=`echo $PACKAGE_VERSION | cut -d. -f1`
		if [ ${FIRST_PART_OF_PKG_VER} -ge 14 ]; then
			if [ ${OS_MAJOR_VER_} -eq 11 ] && [ $SP_ -eq 3 ]; then
				SP_=
			elif [ ${OS_MAJOR_VER_} -eq 12 ] && [ $SP_ -ge 3 ]; then
				SP_=
			elif [ ${OS_MAJOR_VER_} -gt 12 ]; then
				SP_=
			fi
		fi
	else
        SP_=${SYS_DISTRO_SP}
    fi
}

PLEASE_VERIFY_MSG="*** Please verify that you run the latest version of which_ragent_package available at https://ftp-us.imperva.com ***"
FOR_AN_OFFICIAL_LIST_MSG="For an official list of agent packages and their supported platforms, please see the latest SecureSphere Agent Release Notes."

extract_files()
{
	ARCHIVE1=`awk '/^__ARCHIVE1__/ {print NR + 1; exit 0; }' $0`
	ARCHIVE2=`awk '/^__ARCHIVE2__/ {print NR + 1; exit 0; }' $0`
	PKG_ROWS=`expr $ARCHIVE2 - $ARCHIVE1 - 1`
	if [ `uname -s` != "SunOS" ]; then
		TAIL_FLAG="-n"
	fi
	tail ${TAIL_FLAG} +$ARCHIVE1 $0 | head -n $PKG_ROWS > $PKG_FILE
	tail ${TAIL_FLAG} +$ARCHIVE2 $0 > $KABI_FILE
}

usage ()
{
    echo "Usage: which_ragent_package -v <ragent version>"
    cat "${PKG_FILE}" | echo "Available versions are: `grep RELEASE | grep -v 'grep' | awk '{print $2}' | tr '\n' '\ '`"
    echo "Example: which_ragent_package -v 12.0.0"
    echo "$PLEASE_VERIFY_MSG"
}

out()
{
	rm -rf ${KABI_FILE}
	rm -rf ${PKG_FILE}
	exit $1
}

check_version_input()
{
    # Validate input is x.y using regex
    INPUT=`echo "$1" | sed -e 's/[0-9]*\.[0-9]\.[0-9]//'`
    if [ ! -z "$INPUT" ]; then
        return 1
    fi
    X=`grep "RELEASE $1" ${PKG_FILE}`
    return $?
}

check_rhel6_kernel_version()
{
    pkg_version_input=$1
	machine_platform=$2
	RHEL_6K1_CODE=2632431
	RHEL_6_KABI_V=`uname -r | sed 's:\([0-9]*.[0-9]*.[0-9]*-[0-9]*\).*:\1:' | sed 's:\.::g' | sed 's:\-::g'`
	
	if [ $RHEL_6_KABI_V -ge $RHEL_6K1_CODE ]; then # if Kernel ABI >= 2632431 (rhel6 update 5)
	    PKG_NAME=${PKG_NAME}
	elif [ "${pkg_version_input}" = "13.0.0" ]; then # if Kernel ABI < 2632431 (rhel 6 k0) we will recommend the last released rhel6 package that supports k0 driver
	    if [ "${machine_platform}" = "x86_64" ]; then
		    echo ${PKG_NAME} | awk '{print $2}' | grep bigdata >/dev/null 2>&1
		    if [ $? -eq 0 ]; then
			    PKG_NAME_BIG_DATA_AGENT=`echo ${PKG_NAME} | awk '{print $2}'`
			else
			    PKG_NAME_BIG_DATA_AGENT=`echo ${PKG_NAME} | awk '{print $1}'`
			fi
	        PKG_NAME="Imperva-ragent-RHEL-v6-kSMP-px86_64-b13.5.0.21.0.572362.tar.gz ${PKG_NAME_BIG_DATA_AGENT}"
		elif [ "${machine_platform}" = "i386" ]; then
		    PKG_NAME="Imperva-ragent-RHEL-v6-kSMP-pi386-b13.5.0.20.0.567636.tar.gz"
		fi
    elif [ "${pkg_version_input}" = "14.0.0" ]; then
	    if [ "${machine_platform}" = "x86_64" ]; then
		    echo ${PKG_NAME} | awk '{print $2}' | grep bigdata >/dev/null 2>&1
		    if [ $? -eq 0 ]; then
			    PKG_NAME_BIG_DATA_AGENT=`echo ${PKG_NAME} | awk '{print $2}'`
			else
			    PKG_NAME_BIG_DATA_AGENT=`echo ${PKG_NAME} | awk '{print $1}'`
			fi
	        PKG_NAME="Imperva-ragent-RHEL-v6-kSMP-px86_64-b14.1.0.10.0.562096.tar.gz ${PKG_NAME_BIG_DATA_AGENT}"
		elif [ "${machine_platform}" = "i386" ]; then
		    PKG_NAME="Imperva-ragent-RHEL-v6-kSMP-pi386-b14.1.0.10.0.562096.tar.gz"
		fi
	fi
}

print_pkg_name()
{
	OS_STR=$1
	OS_VER=$2
	PLATFORM=$3
	KERNEL=$4
	
	echo "OS: ${OS_STR}"
	echo "Version: ${OS_VER}"
	echo "Platform: ${PLATFORM}"
	if [ -n "${KERNEL}" ]; then
		echo "Kernel: ${KERNEL}"	
	fi
	
	INCLUDE_BIG_DATA_PACKAGE_IN_RESULTS=no
	INCLUDE_OEL6_AS_BD_RHEL6=no
	LATEST_DAM_AGENT_MESSAGE="Latest DAM Agent package is:"
	LATEST_BIG_DATA_AGENT_MESSAGE="Latest Big Data Agent package is:"
	
	version_major=`echo ${version} | cut -d. -f1`
	version_third=`echo ${version} | cut -d. -f3`
	# From v13 and above, if the platform is RHEL/CentOS and the OS verison is 6 or higher, recommend both the SQL Agent and the DAM Agent
	if [ ${version_major} -eq 13 ]; then
		if [ "${OS_STR}" = "RHEL" ] || [ "${OS_STR}" = "CentOS" ]; then
            if [ "${OS_VER}" -eq 6 ] || [ "${OS_VER}" -eq 7 ]; then
                if [ "${PLATFORM}" = x86_64 ]; then
                    INCLUDE_BIG_DATA_PACKAGE_IN_RESULTS=yes
                fi
            fi
        fi
	fi
	
	if [ ${version_major} -ge 14 ]; then
		if [ "${OS_STR}" = "RHEL" ] || [ "${OS_STR}" = "CentOS" ]; then
            if [ "${OS_VER}" -eq 6 ] || [ "${OS_VER}" -eq 7 ] || [ "${OS_VER}" -eq 8 ]; then
                if [ "${PLATFORM}" = x86_64 ] || [ "${PLATFORM}" = ppc64le ]; then
                    INCLUDE_BIG_DATA_PACKAGE_IN_RESULTS=yes
                fi
            fi
        fi
	fi
	
    #
	if [ ${version_major} -ge 14 ]; then
		if [ "${OS_STR}" = "OEL" ] && [ "${OS_VER}" = 6 ]; then
			INCLUDE_OEL6_AS_BD_RHEL6=yes
		fi
	fi
	
	if [ "${INCLUDE_BIG_DATA_PACKAGE_IN_RESULTS}" = "yes" ]; then
	    echo ${PKG_NAME} | awk '{print $2}' | grep bigdata >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			PKG_NAME_SQL_AGENT=`echo ${PKG_NAME} | awk '{print $1}'`
			PKG_NAME_BIG_DATA_AGENT=`echo ${PKG_NAME} | awk '{print $2}'`
		else
			PKG_NAME_SQL_AGENT=`echo ${PKG_NAME} | awk '{print $2}'`
			PKG_NAME_BIG_DATA_AGENT=`echo ${PKG_NAME} | awk '{print $1}'`
		fi
		
		if [ X${PKG_NAME_SQL_AGENT} != X ]; then
			echo "${LATEST_DAM_AGENT_MESSAGE} ${PKG_NAME_SQL_AGENT}"
		fi
		if [ X${PKG_NAME_BIG_DATA_AGENT} != X ]; then
			echo "${LATEST_BIG_DATA_AGENT_MESSAGE} ${PKG_NAME_BIG_DATA_AGENT}"
		fi
	elif [ "${INCLUDE_OEL6_AS_BD_RHEL6}" = "yes" ]; then
	    PKG_NAME_SQL_AGENT=${PKG_NAME}
		PKG_NAME_BIG_DATA_AGENT=`cat ${PKG_FILE} | grep -i "${version}" | grep bigdata-RHEL-v6 | awk '{print $5}'`
		if [ X${PKG_NAME_SQL_AGENT} != X ]; then
			echo "${LATEST_DAM_AGENT_MESSAGE} ${PKG_NAME_SQL_AGENT}"
		fi
		if [ X${PKG_NAME_BIG_DATA_AGENT} != X ]; then
			echo "${LATEST_BIG_DATA_AGENT_MESSAGE} ${PKG_NAME_BIG_DATA_AGENT}"
		fi
	else
	    if [ X${version_third} != X ] && [ ${version_third} -eq 1 ]; then
		    echo "${LATEST_BIG_DATA_AGENT_MESSAGE} ${PKG_NAME}"
		else
		    echo "${LATEST_DAM_AGENT_MESSAGE} ${PKG_NAME}"
		fi
	fi
	echo ""
	echo "The above is a recommendation only. It is not a guarantee of agent support."
	echo "$FOR_AN_OFFICIAL_LIST_MSG"
	
	if [ -n "${PKG_VERB}" ]; then
		PKG_VERZ=`echo $PKG_VERB | awk -F"." '{print $1"."$2}'`
        if [ "${PKG_VERZ}" = "7.5" ] || [ "${PKG_VERZ}" = "8.0" ] || [ "${PKG_VERZ}" = "8.5" ]; then
            PKG_NAMEB=`echo ${PKG_NAME} | sed "s/-b.*-k/-b${PKG_VERB}-k/"`
        else
            PKG_NAMEB=`echo ${PKG_NAME} | sed "s/-b.*/-b${PKG_VERB}.tar.gz/"`
        fi

		echo "Patched ragent package is: ${PKG_NAMEB}"
    fi
	echo
	echo "$PLEASE_VERIFY_MSG"
  
}

get_pkg_name()
{
    version=${1}
    OS_STR=$2
    OS_VER=$3
    PLATFORM=$4
    KERNEL=$5

	version_normal=$version
	# BigData v12 next patch is 12.4.1
	if [ "${version}" = "12.0.1" ]; then
	    version=12.4.1
	fi
	
	if [ "${version}" = "13.0.0" ]; then
	    version=13.[0-9].0
	fi
	
	if [ "${version}" = "14.0.0" ]; then
	    version=14.[0-9].0
	fi
	
	# In VR1 we support also 11.1 version, and in VR2 we support also 11.6 version
	if [ "${version}" = "11.0.0" ]; then
	    version=11.[0-1].0
	fi
	
	if [ "${version}" = "11.5.0" ]; then
	    version=11.[5-6].0
	fi
    
    if [ -z "${KERNEL}" ]; then
        # Ugly hack for Solaris which does not allow empty pattern in grep and for RHEL 3 plain 
        KERNEL=${OS_STR}
    fi
    
	# handle problematic cases in which kernel is smp and not largesmp, hugemum or pae
	if [ "${KERNEL}" = "SMP" ]; then
		PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | grep -v "hugemem" | grep -v "largesmp" | grep -v "pae" | awk -F" " '{print $NF}'`
	# handle problematic cases in which kernel is plain	
	elif [ "${KERNEL}" = "RHEL" ]; then
		PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | grep -v "smp" | grep -v "hugemem" | grep -v "largesmp" | grep -v "pae" | awk -F" " '{print $NF}'`
	elif [ "${OS_STR}" = "UBN" ] && { [ "${OS_VER}" -gt 16 ] || { [ "${OS_VER}" -eq 16 ] && [ "$SYS_DISTRO_SP" -ge 04 ]; }; }; then
	    PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v16" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | grep -v "v14" | head -1 | awk -F" " '{print $NF}'`
	elif [ "${OS_STR}" = "TD-SLE" ] && [ ${PKG_VER_MAJOR_NUM} -ge 14 ]; then
	    PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v11" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | head -1 | awk -F" " '{print $NF}'`
	# The following line is marked as a comment. It help debugging this script in case of wrong package name
	# echo "cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | awk -F\" \" '{print \$NF}'"
	else
		PKG_NAME=`cat ${PKG_FILE} | grep -i "${version}" | grep -i "${OS_STR}" | grep -i "v${OS_VER}" | grep -i "p${PLATFORM}" | grep -i "${KERNEL}" | head -1 | awk -F" " '{print $NF}'`
	fi
    
    if [ "${version}" = "9.5.0" ]; then
        if [ "${KERNEL}" = "UEK-v1-ik1" ]; then
            PKG_NAME="Imperva-ragent-OEL-v5-kUEK1-px86_64-b9.5.0.5009.tar.gz"
        elif [ "${KERNEL}" = "UEK-v1-ik2" ]; then
            PKG_NAME="Imperva-ragent-OEL-v5-kUEK2-px86_64-b9.5.0.5009.tar.gz"
        fi      
    fi
	
	# Ugly code to deal with UBN 14 K2 driver which needs to recommend ZR1P5 and not ZR1P6 for kernel 4.4.0-112
	if [ "${OS_STR}" = "UBN" ]; then
	    UBN14K2_KERNEL=`uname -r | sed 's/-generic//g'`
	    if [ "${version}" = "12.0.0" ] && [ "${OS_VER}" -eq 14 ] && [ "${UBN14K2_KERNEL}" = "4.4.0-112" ]; then
        	PKG_PATCH=`echo "$PKG_NAME" | sed 's/.tar.gz//g' | cut -d . -f4`
			if [ $PKG_PATCH -ge 6000 ] && [ $PKG_PATCH -lt 7000 ]; then
			    PKG_NAME="Imperva-ragent-UBN-v14-kUBN-px86_64-b12.0.0.5116.tar.gz"
			fi
		fi
	fi
	
	if [ "${OS_STR}" = "SLE" ] && [ "$SYS_DISTRO_SP" -eq 2 ]; then
	    if [ "${version_normal}" = "14.0.0" ]; then
		    PKG_NAME="Imperva-ragent-SLE-v12-kSMP-px86_64-b14.4.0.60.0.608806.tar.gz"
		fi
	fi
	
	# From v13.6 and v14.3 we support only RHEL6 K1, because RHEL6 K0 is EOL (except bigdata agent which doesn't load driver)
	if [ "${OS_STR}" = "RHEL" ] && [ "${OS_VER}" = "6" ]; then
	    if [ "${version_normal}" = "13.0.0" ] || [ "${version_normal}" = "14.0.0" ]; then
	        check_rhel6_kernel_version ${version_normal} ${PLATFORM}
		fi
    fi

	if [ -z "${PKG_NAME}" ]; then
        if [ -z "${PKG_VERB}" ]; then
		    echo "Could not find appropriate package for version ${version_normal} on this machine."
			echo ""
			echo "----------------------------------"
			echo "If you cannot find a valid package for any version and you want to talk to Imperva support about this, please provide them with the following details:"
            echo "Kernel: ${KERNEL}"
            echo "OS Name: ${OS_STR}"
            echo "OS Version: ${OS_VER}"
			echo "Service Pack: ${SYS_DISTRO_SP}"
            echo "Platform: ${PLATFORM}"
            echo "Version: ${version_normal}"
            echo "----------------------------------"
            echo ""
            echo "$FOR_AN_OFFICIAL_LIST_MSG"
            echo ""
            echo "$PLEASE_VERIFY_MSG"
            if [ "${OS_STR}" = "SunOS" ] && [ "${OS_VER}" = "dummy_sol_11_1" ]; then
                echo ""
                echo "Minimal Solaris 11.1 supported branch is: 0.175.1.15.0.4.0" 
                echo "Please upgrade the system to that branch or higher."
            fi
		    out 1
        fi
	fi
}

############################
###### Main flow ###########
############################
if [ -z "$1" ]; then
    extract_files
	usage
	out 0
fi

ALLOW_CENTOS=no
while [ -n "$1" ]
do
    switch=$1
    shift
    case ${switch} in
    -h) extract_files
	    usage 
		out 0;;
	-f) extract_files
		echo "Packages file: ${PKG_FILE}"
		echo "Kabi file: ${KABI_FILE}"
		exit 0;;
	-b) PKG_VERB=$1
        shift;;
    -v) PKG_VER=$1
		shift;;
    -c) ALLOW_CENTOS=yes
        shift;;    
	 *) extract_files
	    usage
		out 0;;
    esac
done

PKG_VER_MAJOR_NUM=`echo "${PKG_VER}" | cut -d. -f1`
if [ $PKG_VER_MAJOR_NUM -ge 12 ]; then
    ALLOW_CENTOS=yes    
fi

extract_files

if [ ! -f "${KABI_FILE}" -o ! -f "${PKG_FILE}" ]; then
	echo "Bsx extraction failed."
	out 1
fi

if [ -z "${PKG_VER}" ]; then
    if [ -z "${PKG_VERB}" ]; then
        usage
        out 0
	else
        PKG_VER=`echo $PKG_VERB | awk -F"." '{print $1"."$2}'`
        grep "RELEASE $PKG_VER" $PKG_FILE > /dev/null
        if [ $? -ne 0 ]; then
            PKG_VER=`cat $PKG_FILE | grep RELEASE | tail -n -1 | awk '{print $NF}'`
        fi
    fi
fi

INPUT_SMALL=`echo "$PKG_VER" | sed -e 's/[0-9]*\.[0-9]//'`
if [ -z "$INPUT_SMALL" ]; then
    PKG_VER=${PKG_VER}.0
fi

# We support only versions 9.0.0-13.3.0 for now, which can be found in packages.txt file
check_version_input $PKG_VER
if [ $? -eq 1 ]; then
    usage
    out 0
fi

get_sys_os
if [ "${SYS_OS}" = "Linux" ]; then
    if is_xen; then
        if is_rhel; then
		    init_linux_rhel_xen_vars
		    get_pkg_name "${PKG_VER}" "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "XEN"
		    print_pkg_name "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "XEN"
        elif is_suse; then
            init_linux_suse_xen_vars
			get_pkg_name "${PKG_VER}" "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "XEN"
		    print_pkg_name "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "XEN"
        fi
	elif is_uek; then
		init_linux_uek_vars "${PKG_VER}"
		get_pkg_name "${PKG_VER}" "OEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
		print_pkg_name "OEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
	elif is_td; then
	    init_linux_td_vars "${PKG_VER}"
		get_pkg_name "${PKG_VER}" "TD-SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
		print_pkg_name "TD-SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL}"
	elif is_suse; then
	    init_linux_suse_vars "${PKG_VER}"
		if [ "${PKG_VER}" = "8.0" -o "${PKG_VER}" = "8.5" ]; then
			SYS_DISTRO_VERSION="SLE${SYS_DISTRO_VERSION}"
		fi
		if [ "${SYS_DISTRO_VERSION}" = 15 ]; then
		    get_pkg_name "${PKG_VER}" "SLE" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
		elif [ "${SYS_DISTRO_VERSION}" = 12 ]; then
		    if [ ${PKG_VER_MAJOR_NUM} -ge 14 ]; then
			    get_pkg_name "${PKG_VER}" "SLE" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
			else
			    get_pkg_name "${PKG_VER}" "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
			fi
		else
		    get_pkg_name "${PKG_VER}" "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
		fi
		if [ "${SYS_DISTRO_VERSION}" = 15 ]; then
		    print_pkg_name "SLE" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
		elif [ "${SYS_DISTRO_VERSION}" = 12 ]; then
		    if [ ${PKG_VER_MAJOR_NUM} -ge 14 ]; then
			    print_pkg_name "SLE" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
			else
			    print_pkg_name "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
			fi
		else
		    print_pkg_name "SLE" "${SYS_DISTRO_VERSION}SP${SYS_DISTRO_SP}" "${SYS_PLATFORM}" "${SYS_KERNEL_CONFIG}"
		fi
	elif is_ubuntu; then
		init_linux_ubuntu_vars	
        get_pkg_name "${PKG_VER}" "UBN" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" 
		print_pkg_name "UBN" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	elif is_rhel; then
        init_linux_rhel_vars "${PKG_VER}"
		get_pkg_name "${PKG_VER}" "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SMP_STRING}"
        if [ $IS_CENTOS = yes ]; then
		    print_pkg_name "CentOS" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SMP_STRING}"
        else
            print_pkg_name "RHEL" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}" "${SMP_STRING}"
        fi 				
	else
		echo "Unsupported Linux distribution"
		out 1
	fi
elif [ "${SYS_OS}" = "SunOS" ]; then
	init_sunos_vars "${PKG_VER}"
	get_pkg_name "${PKG_VER}" "SunOS" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	print_pkg_name "SunOS" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
elif [ "${SYS_OS}" = "HPUX" ]; then
	init_hpux_vars
	PKG_VER_NUM=`echo "${PKG_VER}" | tr -d "."`
	if [ ${PKG_VER_NUM} -ge 90 ]; then
		SYS_DISTRO_VERSION=`uname -r | awk -F. '{print $2"."$3}'`
	else
		SYS_DISTRO_VERSION=`uname -r`
	fi
	get_pkg_name "${PKG_VER}" "HPUX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	print_pkg_name "HPUX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
elif [ "${SYS_OS}" = "AIX" ]; then
	init_aix_vars
	get_pkg_name "${PKG_VER}" "AIX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
	print_pkg_name "AIX" "${SYS_DISTRO_VERSION}" "${SYS_PLATFORM}"
else
	echo "Unsupported OS"
	out 1
fi
out 0

__ARCHIVE1__

PACKAGES_VERSION 0234
RELEASE 12.0.0
aix		v61	powerpc64		aix	 Imperva-ragent-AIX-v61-ppowerpc64-b12.0.0.8030.tar.gz
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b12.0.0.8030.tar.gz
aix		v72	powerpc64		aix	 Imperva-ragent-AIX-v72-ppowerpc64-b12.0.0.8030.tar.gz
hpux		v11.11	hppa		hpux	 Imperva-ragent-HPUX-v11.11-phppa-b12.0.0.7050.tar.gz
hpux		v11.23	hppa		hpux	 Imperva-ragent-HPUX-v11.23-phppa-b12.0.0.7050.tar.gz
hpux		v11.23	ia64		hpux	 Imperva-ragent-HPUX-v11.23-pia64-b12.0.0.7050.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b12.0.0.7050.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b12.0.0.7050.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b12.0.0.8030.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b12.0.0.8030.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b12.0.0.8030.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b12.0.0.8030.tar.gz
oel		v5	x86_64		uek-v1-ik4	 Imperva-ragent-OEL-v5-kUEK-v1-ik4-px86_64-b12.0.0.8030.tar.gz
oel		v5	x86_64		uek-v2	 Imperva-ragent-OEL-v5-kUEK-v2-px86_64-b12.0.0.8030.tar.gz
oel		v6	x86_64		uek-v3	 Imperva-ragent-OEL-v6-kUEK-v3-px86_64-b12.0.0.8030.tar.gz
oel		v7	x86_64		uek-v3	 Imperva-ragent-OEL-v7-kUEK-v3-px86_64-b12.0.0.8030.tar.gz
oel		v6	x86_64		uek-v4	 Imperva-ragent-OEL-v6-kUEK-v4-px86_64-b12.0.0.8026.tar.gz
oel		v7	x86_64		uek-v4	 Imperva-ragent-OEL-v7-kUEK-v4-px86_64-b12.0.0.8026.tar.gz
rhel		v4	i386		smp	 Imperva-ragent-RHEL-v4-kSMP-pi386-b12.0.0.7050.tar.gz
rhel		v4	i386		hugemem	 Imperva-ragent-RHEL-v4-kHUGEMEM-pi386-b12.0.0.7050.tar.gz
rhel		v4	x86_64		largesmp	 Imperva-ragent-RHEL-v4-kLARGESMP-px86_64-b12.0.0.7050.tar.gz
rhel		v4	x86_64		smp	 Imperva-ragent-RHEL-v4-kSMP-px86_64-b12.0.0.7050.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b12.0.0.8026.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b12.0.0.8026.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b12.0.0.8026.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b12.0.0.8026.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b12.0.0.8026.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b12.0.0.8026.tar.gz
rhel		v7	x86_64		smp	 Imperva-ragent-RHEL-v7-kSMP-px86_64-b12.0.0.8026.tar.gz
sle		v11SP2	x86_64		smp	 Imperva-ragent-SLE-v11SP2-kSMP-px86_64-b12.0.0.7050.tar.gz
sle		v11SP3	x86_64		smp	 Imperva-ragent-SLE-v11SP3-kSMP-px86_64-b12.0.0.7050.tar.gz
sle		v11SP3	x86_64		bigsmp	 Imperva-ragent-SLE-v11SP3-kBIGSMP-px86_64-b12.0.0.7050.tar.gz
sle		v11SP4	x86_64		smp	 Imperva-ragent-SLE-v11SP4-kSMP-px86_64-b12.0.0.8031.tar.gz
sle		v12SP0	x86_64		smp	 Imperva-ragent-SLE-v12SP0-kSMP-px86_64-b12.0.0.7050.tar.gz
sle		v12SP1	x86_64		smp	 Imperva-ragent-SLE-v12SP1-kSMP-px86_64-b12.0.0.7050.tar.gz
sle		v12SP2	x86_64		smp	 Imperva-ragent-SLE-v12SP2-kSMP-px86_64-b12.0.0.8030.tar.gz
sle		v12SP3	x86_64		smp	 Imperva-ragent-SLE-v12SP3-kSMP-px86_64-b12.0.0.8030.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b12.0.0.7050.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b12.0.0.7050.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b12.0.0.8032.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b12.0.0.8032.tar.gz
TD-SLE		v11SP1	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP1-kTD-px86_64-b12.0.0.8030.tar.gz
TD-SLE		v11SP1	x86_64		TD-ik2	 Imperva-ragent-TD-SLE-v11SP1-kTD-ik2-px86_64-b12.0.0.8030.tar.gz
TD-SLE		v10SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v10SP3-kTD-px86_64-b12.0.0.8030.tar.gz
TD-SLE		v11SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP3-kTD-px86_64-b12.0.0.8033.tar.gz
UBN		v14	x86_64		UBN	 Imperva-ragent-UBN-v14-kUBN-px86_64-b12.0.0.7050.tar.gz
RELEASE 12.0.1
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b12.4.1.8542.tar.gz
rhel		v7	x86_64		smp	 Imperva-ragent-RHEL-v7-kSMP-px86_64-b12.4.1.8542.tar.gz
RELEASE 13.0.0
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b13.6.0.40.0.588301.tar.gz
aix		v72	powerpc64		aix	 Imperva-ragent-AIX-v72-ppowerpc64-b13.6.0.40.0.588301.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b13.6.0.40.0.588301.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b13.6.0.40.0.588301.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b13.5.0.20.0.569909.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b13.5.0.20.0.569909.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b13.5.0.20.0.569909.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b13.6.0.40.0.588301.tar.gz
oel		v5	x86_64		uek-v1-ik4	 Imperva-ragent-OEL-v5-kUEK-v1-ik4-px86_64-b13.5.0.20.0.569909.tar.gz
oel		v5	x86_64		uek-v2	 Imperva-ragent-OEL-v5-kUEK-v2-px86_64-b13.6.0.40.0.588301.tar.gz
oel		v6	x86_64		uek-v3	 Imperva-ragent-OEL-v6-kUEK-v3-px86_64-b13.6.0.40.0.588301.tar.gz
oel		v7	x86_64		uek-v3	 Imperva-ragent-OEL-v7-kUEK-v3-px86_64-b13.6.0.40.0.588301.tar.gz
oel		v6	x86_64		uek-v4	 Imperva-ragent-OEL-v6-kUEK-v4-px86_64-b13.6.0.40.0.588301.tar.gz
oel		v7	x86_64		uek-v4	 Imperva-ragent-OEL-v7-kUEK-v4-px86_64-b13.6.0.40.0.588301.tar.gz
oel		v7	x86_64		uek-v5	 Imperva-ragent-OEL-v7-kUEK-v5-px86_64-b13.6.0.70.0.615836.tar.gz
oel		v7	x86_64		uek-v6	 Imperva-ragent-OEL-v7-kUEK-v6-px86_64-b13.6.0.70.0.615836.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b13.6.0.40.0.588301.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b13.6.0.40.0.588301.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b13.6.0.40.0.588301.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b13.6.0.40.0.588301.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b13.6.0.60.0.604640.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b13.6.0.60.0.604640.tar.gz
rhel		v7	x86_64		smp	 Imperva-ragent-RHEL-v7-kSMP-px86_64-b13.6.0.60.0.604640.tar.gz
sle		v11SP3	x86_64		smp	 Imperva-ragent-SLE-v11SP3-kSMP-px86_64-b13.2.0.10.0.545875.tar.gz
sle		v11SP3	x86_64		bigsmp	 Imperva-ragent-SLE-v11SP3-kBIGSMP-px86_64-b13.2.0.10.0.545875.tar.gz
sle		v11SP4	x86_64		smp	 Imperva-ragent-SLE-v11SP4-kSMP-px86_64-b13.6.0.40.0.588301.tar.gz
sle		v12SP0	x86_64		smp	 Imperva-ragent-SLE-v12SP0-kSMP-px86_64-b13.2.0.10.0.545875.tar.gz
sle		v12SP1	x86_64		smp	 Imperva-ragent-SLE-v12SP1-kSMP-px86_64-b13.2.0.10.0.545875.tar.gz
sle		v12SP2	x86_64		smp	 Imperva-ragent-SLE-v12SP2-kSMP-px86_64-b13.6.0.60.0.604640.tar.gz
sle		v12SP3	x86_64		smp	 Imperva-ragent-SLE-v12SP3-kSMP-px86_64-b13.6.0.60.0.604640.tar.gz
sle		v12SP4	x86_64		smp	 Imperva-ragent-SLE-v12SP4-kSMP-px86_64-b13.6.0.60.0.604640.tar.gz
sle		v12SP5	x86_64		smp	 Imperva-ragent-SLE-v12SP5-kSMP-px86_64-b13.6.0.60.0.604640.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b13.6.0.40.0.588301.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b13.6.0.40.0.588301.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b13.6.0.40.0.588301.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b13.6.0.40.0.588301.tar.gz
TD-SLE		v11SP1	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP1-kTD-px86_64-b13.5.0.20.0.567636.tar.gz
TD-SLE		v11SP1	x86_64		TD-ik2	 Imperva-ragent-TD-SLE-v11SP1-kTD-ik2-px86_64-b13.5.0.20.0.567636.tar.gz
TD-SLE		v10SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v10SP3-kTD-px86_64-b13.5.0.20.0.567636.tar.gz
TD-SLE		v11SP3	x86_64		TD	 Imperva-ragent-TD-SLE-v11SP3-kTD-px86_64-b13.6.0.60.0.604640.tar.gz
UBN		v14	x86_64		UBN	 Imperva-ragent-UBN-v14-kUBN-px86_64-b13.5.0.20.0.567636.tar.gz
UBN		v16+	x86_64		UBN	 Imperva-ragent-UBN-px86_64-b13.6.0.60.0.604640.tar.gz
bigdata-RHEL		v6	x86_64		smp	 Imperva-ragent-bigdata-RHEL-v6-kSMP-px86_64-b13.3.0.10.0.555141.tar.gz
bigdata-RHEL		v7	x86_64		smp	 Imperva-ragent-bigdata-RHEL-v7-kSMP-px86_64-b13.3.0.10.0.555141.tar.gz
RELEASE 14.0.0
aix		v71	powerpc64		aix	 Imperva-ragent-AIX-v71-ppowerpc64-b14.4.0.80.0.613296.tar.gz
aix		v72	powerpc64		aix	 Imperva-ragent-AIX-v72-ppowerpc64-b14.4.0.80.0.613296.tar.gz
hpux		v11.31	hppa		hpux	 Imperva-ragent-HPUX-v11.31-phppa-b14.1.0.10.0.562096.tar.gz
hpux		v11.31	ia64		hpux	 Imperva-ragent-HPUX-v11.31-pia64-b14.1.0.10.0.562096.tar.gz
oel		v5	x86_64		uek-v1-ik1	 Imperva-ragent-OEL-v5-kUEK-v1-ik1-px86_64-b14.1.0.10.0.562096.tar.gz
oel		v5	x86_64		uek-v1-ik2	 Imperva-ragent-OEL-v5-kUEK-v1-ik2-px86_64-b14.1.0.10.0.562096.tar.gz
oel		v5	x86_64		uek-v1-ik3	 Imperva-ragent-OEL-v5-kUEK-v1-ik3-px86_64-b14.1.0.10.0.562096.tar.gz
oel		v6	x86_64		uek-v2	 Imperva-ragent-OEL-v6-kUEK-v2-px86_64-b14.1.0.20.0.569078.tar.gz
oel		v5	x86_64		uek-v1-ik4	 Imperva-ragent-OEL-v5-kUEK-v1-ik4-px86_64-b14.1.0.10.0.562096.tar.gz
oel		v5	x86_64		uek-v2	 Imperva-ragent-OEL-v5-kUEK-v2-px86_64-b14.1.0.10.0.562096.tar.gz
oel		v6	x86_64		uek-v3	 Imperva-ragent-OEL-v6-kUEK-v3-px86_64-b14.1.0.20.0.569078.tar.gz
oel		v7	x86_64		uek-v3	 Imperva-ragent-OEL-v7-kUEK-v3-px86_64-b14.4.0.70.0.610268.tar.gz
oel		v6	x86_64		uek-v4	 Imperva-ragent-OEL-v6-kUEK-v4-px86_64-b14.1.0.20.0.569078.tar.gz
oel		v7	x86_64		uek-v4	 Imperva-ragent-OEL-v7-kUEK-v4-px86_64-b14.4.0.100.0.615340.tar.gz
oel		v7	x86_64		uek-v5	 Imperva-ragent-OEL-v7-kUEK-v5-px86_64-b14.4.0.70.0.610252.tar.gz
oel		v7	x86_64		uek-v6	 Imperva-ragent-OEL-v7-kUEK-v6-px86_64-b14.4.0.70.0.610252.tar.gz
oel		v8	x86_64		uek-v6	 Imperva-ragent-OEL-v8-kUEK-v6-px86_64-b14.4.0.60.0.608806.tar.gz
rhel		v5	i386		pae	 Imperva-ragent-RHEL-v5-kPAE-pi386-b14.1.0.10.0.562096.tar.gz
rhel		v5	i386		smp	 Imperva-ragent-RHEL-v5-kSMP-pi386-b14.1.0.10.0.562096.tar.gz
rhel		v5	x86_64		smp	 Imperva-ragent-RHEL-v5-kSMP-px86_64-b14.1.0.10.0.562096.tar.gz
rhel		v5	x86_64		xen	 Imperva-ragent-RHEL-v5-kXEN-px86_64-b14.1.0.10.0.562096.tar.gz
rhel		v6	i386		smp	 Imperva-ragent-RHEL-v6-kSMP-pi386-b14.1.0.10.0.562096.tar.gz
rhel		v6	x86_64		smp	 Imperva-ragent-RHEL-v6-kSMP-px86_64-b14.4.0.90.0.614557.tar.gz
rhel		v7	x86_64		smp	 Imperva-ragent-RHEL-v7-kSMP-px86_64-b14.4.0.100.0.615340.tar.gz
rhel		v7	ppc64le		smp	 Imperva-ragent-RHEL-v7-kSMP-pppc64le-b14.4.0.40.0.606176.tar.gz
rhel		v8	x86_64		smp	 Imperva-ragent-RHEL-v8-kSMP-px86_64-b14.4.0.100.0.615340.tar.gz
sle		v11SP4	x86_64		smp	 Imperva-ragent-SLE-v11SP4-kSMP-px86_64-b14.1.0.10.0.562096.tar.gz
sle		v12	x86_64		smp	 Imperva-ragent-SLE-v12-kSMP-px86_64-b14.4.0.80.0.612150.tar.gz
sle		v15	x86_64		smp	 Imperva-ragent-SLE-v15-kSMP-px86_64-b14.4.0.60.0.608806.tar.gz
SunOS		v5.10	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.10-psparcv9-b14.4.0.50.0.607477.tar.gz
SunOS		v5.10	x86_64		SunOS	 Imperva-ragent-SunOS-v5.10-px86_64-b14.4.0.90.0.614557.tar.gz
SunOS		v5.11	x86_64		SunOS	 Imperva-ragent-SunOS-v5.11-px86_64-b14.4.0.90.0.614557.tar.gz
SunOS		v5.11	sparcv9		SunOS	 Imperva-ragent-SunOS-v5.11-psparcv9-b14.4.0.50.0.607477.tar.gz
TD-SLE		v11+	x86_64		TD-SLE	 Imperva-ragent-TD-SLE-px86_64-b14.4.0.40.0.606176.tar.gz
UBN		v14	x86_64		UBN	 Imperva-ragent-UBN-v14-kUBN-px86_64-b14.1.0.10.0.562096.tar.gz
UBN		v16+	x86_64		UBN	 Imperva-ragent-UBN-px86_64-b14.4.0.90.0.614557.tar.gz
bigdata-RHEL		v6	x86_64		smp	 Imperva-ragent-bigdata-RHEL-v6-kSMP-px86_64-b14.4.0.80.0.613303.tar.gz
bigdata-RHEL		v7v8	x86_64		smp	 Imperva-ragent-bigdata-RHEL-kSMP-px86_64-b14.4.0.80.0.613303.tar.gz
bigdata-RHEL		v7v8	ppc64le		smp	 Imperva-ragent-bigdata-RHEL-kSMP-pppc64le-b14.4.0.80.0.613303.tar.gz
__ARCHIVE2__
KABI_VERSION 0081
#dist               agent sig       min kern patch      max kern patch         additional_os_info   optional_data
SLE.9.3.i386        0               0                   99999              
SLE.9.3.x86_64      2481918936      0                   99999              
SLE.9.3.x86_64      3766268762      0                   99999              
SLE.9.4.x86_64      3384926936      0                   99999              
SLE.9.4.x86_64      3686701036      0                   99999              
SLE.10.1.x86_64     2103713736      0                   99999              
SLE.10.1.x86_64     2350452553      0                   99999              
SLE.10.1.x86_64     3542803736      0                   99999              
SLE.10.2.x86_64     2103713736      0                   99999              
SLE.10.2.x86_64     2350452553      0                   99999              
SLE.10.2.x86_64     3542803736      0                   99999
SLE.10.3.x86_64     2103713736      0                   99999
SLE.10.3.x86_64     2350452553      0                   99999
SLE.10.3.x86_64     3542803736      0                   99999
SLE.10.4.x86_64     2350452553      0                   99999              
SLE.10.4.x86_64     3542803736      0                   99999
SLE.10.0.x86_64     2103713736      0                   99999
SLE.10.0.x86_64     2350452553      0                   99999              
SLE.10.0.x86_64     3542803736      0                   99999
SLE.11.0.i386       0               0                   99999
SLE.11.1.x86_64     28697893        0                   99999
SLE.11.1.x86_64     3553360080      0                   99999              
SLE.11.1.x86_64     1954018875      0                   99999
SLE.11.2.x86_64     2350452559      0                   99999
SLE.11.3.x86_64     0               0                   99999
SLE.11.4.x86_64     0               0                   99999
SLE.12.0.x86_64     0               0                   99999     
SLE.12.1.x86_64     0               0                   99999      
SLE.12.2.x86_64     0               0                   99999
SLE.12.3.x86_64     0               0                   99999
SLE.12.4.x86_64     0               0                   99999
SLE.12.5.x86_64     0               0                   99999
UEK1                0               2.6.32-100.26.2     2.6.32-100.26.2        el5                 UEK-v1-ik1
UEK2                0               2.6.32-300.7.1      2.6.32-300.39.2        el5                 UEK-v1-ik2
UEK3                0               2.6.32-400.21.1     2.6.32-400.21.1        el5                 UEK-v1-ik3
UEK4                0               2.6.39-400.17.1     2.6.39-400.9999.9999   el6                 UEK-v2
UEK5                0               2.6.32-400.23       2.6.32-400.9999.9999   el5                 UEK-v1-ik4
UEK6                0               2.6.39-400.17.1     2.6.39-400.9999.9999   el5                 UEK-v2
UEK7                0               3.8.13-16           3.8.13-9999.9999.9999  el6                 UEK-v3
UEK8                0               3.8.13-35.3.1       3.8.13-9999.9999.9999  el7                 UEK-v3
UEK9                0               4.1.12-32           4.1.12-9999.9999.9999  el6                 UEK-v4
UEK10               0               4.1.12-32           4.1.12-9999.9999.9999  el7                 UEK-v4
UEK11               0               4.14.35-1818.3.3    4.14.35-9999.9999.9999 el7                 UEK-v5
UEK12               0               5.4.17-2011.2.2     5.4.17-9999.9999.9999  el7                 UEK-v6
UEK13               0               5.4.17-2011.2.2     5.4.17-9999.9999.9999  el8                 UEK-v6
TD                  0               2.6.32.54-0.23      2.6.32.54-0.23                             TD
TD2                 0               2.6.16.60-0.91      2.6.16.60-0.9999                           TD
TD3                 0               2.6.32.54-0.35      2.6.32.54-0.9999                           TD-ik2
TD4                 0               3.0.101-0.101       3.0.101-0.9999                             TD
UBN.14.04           0               4.2.0-27            4.2.0-27               14.04               UBN-ik0 
UBN.14.04           0               4.4.0-34            4.4.0-34               14.04               UBN-ik1
UBN.14.04           0               4.4.0-112           4.4.0-112              14.04               UBN-ik2
# agent version -> agent signature mapping:
# RRR1P1: 2103713736
# RRR1P2: 2103713736
# RRR2: 2103713736
# RRR2P1: 2103713736
# RRR2P2: 2103713736, 28697893
# RRR2P3: 2350452553, 3553360080, 2481918936, 3384926936
# SR1: 2350452553, 3553360080, 2481918936, 3384926936
# SR2: 3766268762, 3686701036, 3542803736, 1954018875

