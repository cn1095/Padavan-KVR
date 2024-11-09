#!/bin/sh
#20200426 chongshengB
#20210410 xumng123
#20240831 fightround
PROG=/etc/storage/bin/zerotier-one
PROGCLI=/etc/storage/bin/zerotier-cli
PROGIDT=/etc/storage/bin/zerotier-idtool
config_path="/etc/storage/zerotier-one"
user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
github_proxys="$(nvram get github_proxy)"
start_instance() {
	port=""
	args=""
	nwid="$(nvram get zerotier_id)"
	moonid="$(nvram get zerotier_moonid)"
	secret="$(nvram get zerotier_secret)"
	mkdir -p $config_path/networks.d
	mkdir -p $config_path/moons.d
	if [ -n "$port" ]; then
		args="$args -p$port"
	fi
	if [ -z "$secret" ]; then
		logger -t "zerotier" "密匙为空,正在生成密匙,请稍后..."
		sf="$config_path/identity.secret"
		pf="$config_path/identity.public"
		$PROGIDT generate "$sf" "$pf"  >/dev/null
		[ $? -ne 0 ] && return 1
		secret="$(cat $sf)"
		#rm "$sf"
		nvram set zerotier_secret="$secret"
		nvram commit
	else
		logger -t "zerotier" "找到密匙,正在写入文件,请稍后..."
		echo "$secret" >$config_path/identity.secret
		$PROGIDT getpublic $config_path/identity.secret >$config_path/identity.public
		#rm -f $config_path/identity.public
	fi
	logger -t "zerotier" "启动 $PROG $args $config_path"
	$PROG $args $config_path >/dev/null 2>&1 &

	while [ ! -f $config_path/zerotier-one.port ]; do
		sleep 1
	done
	if [ -n "$moonid" ]; then
		$PROGCLI orbit $moonid $moonid
		logger -t "zerotier" "加入moon: $moonid 成功!"
	fi
	if [ -n "$nwid" ]; then
		$PROGCLI join $nwid
		logger -t "zerotier" "加入网络: $nwid 成功!"
		rules

	fi
}

rules() {
	while [ "$(ifconfig | grep zt | awk '{print $1}')" = "" ]; do
		sleep 1
	done
	nat_enable=$(nvram get zerotier_nat)
	zt0=$(ifconfig | grep zt | awk '{print $1}')
	del_rules
 	logger -t "zerotier" "添加防火墙规则中..."
	iptables -I INPUT -i $zt0 -j ACCEPT
	iptables -I FORWARD -i $zt0 -o $zt0 -j ACCEPT
	iptables -I FORWARD -i $zt0 -j ACCEPT
	if [ $nat_enable -eq 1 ]; then
		iptables -t nat -I POSTROUTING -o $zt0 -j MASQUERADE
		while [ "$(ip route | grep -E "dev\s+$zt0\s+proto\s+kernel"| awk '{print $1}')" = "" ]; do
		    sleep 1
		done
		ip_segment=$(ip route | grep -E "dev\s+$zt0\s+proto\s+kernel"| awk '{print $1}')
                logger -t "zerotier" "$zt0 网段为$ip_segment 添加进NAT规则中..."
		iptables -t nat -I POSTROUTING -s $ip_segment -j MASQUERADE
	fi
	logger -t "zerotier" "zerotier接口: $zt0 启动成功!"
 	count=0
        while [ $count -lt 5 ]
        do
       ztstatus=$($PROGCLI info | awk '{print $5}')
       if [ "$ztstatus" = "OFFLINE" ]; then
	        sleep 2
        elif [ "$ztstatus" = "ONLINE" ]; then
        	ztid=$($PROGCLI info | awk '{print $3}')
        	logger -t "zerotier" "若官网没有此设备，请收到绑定此设备ID $ztid "
        	break
        fi
        count=$(expr $count + 1)
        done
	if [ "$($PROGCLI info | awk '{print $5}')" = "OFFLINE" ] ; then
	  logger -t "zerotier" "当前zerotier未上线，可能你的网络无法链接到zerotier官方服务器！"
          exit 1
        fi
}

del_rules() {
	zt0=$(ifconfig | grep zt | awk '{print $1}')
	ip_segment=$(ip route | grep -E "dev\s+$zt0\s+proto\s+kernel"| awk '{print $1}')
	logger -t "zerotier" "删除防火墙规则中..."
	iptables -D INPUT -i $zt0 -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i $zt0 -o $zt0 -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i $zt0 -j ACCEPT 2>/dev/null
	iptables -t nat -D POSTROUTING -o $zt0 -j MASQUERADE 2>/dev/null
	iptables -t nat -D POSTROUTING -s $ip_segment -j MASQUERADE 2>/dev/null
}

start_zero() {
	logger -t "zerotier" "正在启动zerotier"
 	if [ ! -f "$PROG" ] ; then
		logger -t "zerotier" "主程序${$PROG}不存在，开始在线下载..."
  		[ ! -d /etc/storage/bin ] && mkdir -p /etc/storage/bin
  		curltest=`which curl`
    		if [ -z "$curltest" ] || [ ! -s "`which curl`" ] ; then
      			tag="$( wget -T 5 -t 3 --user-agent "$user_agent" --max-redirect=0 --output-document=-  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
	 		[ -z "$tag" ] && tag="$( wget -T 5 -t 3 --user-agent "$user_agent" --quiet --output-document=-  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest  2>&1 | grep 'tag_name' | cut -d\" -f4 )"
    		else
      			tag="$( curl --connect-timeout 3 --user-agent "$user_agent"  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
       			[ -z "$tag" ] && tag="$( curl -L --connect-timeout 3 --user-agent "$user_agent" -s  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest  2>&1 | grep 'tag_name' | cut -d\" -f4 )"
       		fi
	 	[ -z "$tag" ] && tag="1.14.2"
   		logger -t "zerotier" "开始下载 https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one 到 $PROG"
     		for proxy in $github_proxys ; do
       			curl -Lkso "$PROG" "${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one" || wget --no-check-certificate -q -O "$PROG" "${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one" || curl -Lkso "$PROG" "https://fastly.jsdelivr.net/gh/lmq8267/ZeroTierOne@master/install/${tag}/zerotier-one" || wget --no-check-certificate -q -O "$PROG" "https://fastly.jsdelivr.net/gh/lmq8267/ZeroTierOne@master/install/${tag}/zerotier-one"
       			if [ "$?" = 0 ] ; then
	  			chmod +x $PROG
      				if [ $(($($PROG -h | wc -l))) -gt 3 ] ; then
	  				logger -t "zerotier" "$PROG 下载成功"
       				else
	   				logger -t "zerotier" "下载失败，请手动下载 https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one 上传到  $PROG"
					exit 1
	  			fi
	  		else
				logger -t "zerotier" "下载失败，请手动下载 https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one 上传到  $PROG"
				exit 1
   			fi
	 	done
  	fi
   	[ ! -L "$PROGCLI" ] && ln -sf $PROG $PROGCLI
    	[ ! -L "$PROGIDT" ] && ln -sf $PROG $PROGIDT
	kill_z
	start_instance 'zerotier'

}
kill_z() {
	zerotier_process=$(pidof zerotier-one)
	if [ -n "$zerotier_process" ]; then
		logger -t "zerotier" "有进程 $zerotier_proces 在运行，结束中..."
		killall zerotier-one >/dev/null 2>&1
		kill -9 "$zerotier_process" >/dev/null 2>&1
	fi
}
stop_zero() {
    logger -t "zerotier" "正在关闭zerotier..."
	del_rules
	kill_z
	rm -rf $config_path
	logger -t "zerotier" "zerotier关闭成功!"
}

case $1 in
start)
	start_zero
	;;
stop)
	stop_zero
	;;
*)
	echo "check"
	#exit 0
	;;
esac
