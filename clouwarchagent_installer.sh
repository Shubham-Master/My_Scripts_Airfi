#!/bin/bash
set -euo pipefail

USER="ubuntu"  
SCRIPT_NAME="cloudwatch_install.sh"

get_hosts() {
    if [ "$#" -eq 0 ]; then
        echo "Enter space-separated hostnames or IPs:"
        read -r -a HOSTS
    else
        HOSTS=("$@")
    fi
}

generate_install_script() {
    cat >"$SCRIPT_NAME" <<'EOF'
#!/bin/bash
set -euxo pipefail
cd /dev/shm/
sudo apt update -y
sudo apt install curl jq -y

echo "Installing CloudWatch Agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

CONFIG_PATH="/opt/aws/amazon-cloudwatch-agent/bin/config.json"
sudo tee "$CONFIG_PATH" > /dev/null << 'JSON'
{
  "agent": {
    "metrics_collection_interval": 30,
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent", "used", "total", "free"],
        "metrics_collection_interval": 30,
        "resources": ["/media", "/"]
      },
      "mem": {
        "measurement": ["mem_used_percent", "used", "total", "available"],
        "metrics_collection_interval": 30
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "Name": "UNKNOWN"
    }
  }
}
JSON
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
NAME_TAG=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance/Name || true)
if [[ -z "$NAME_TAG" || "$NAME_TAG" == *"404"* || "$NAME_TAG" == *"Not Found"* ]]; then
    NAME_TAG=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
fi
jq --arg nametag "$NAME_TAG" '.metrics.append_dimensions.Name = $nametag'  $CONFIG_PATH  > /tmp/tmp.json
sudo mv /tmp/tmp.json $CONFIG_PATH
cat $CONFIG_PATH
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:$CONFIG_PATH -s
sudo systemctl enable amazon-cloudwatch-agent
EOF

    chmod +x "$SCRIPT_NAME"
}

run_install_on_hosts() {
    for HOST in "${HOSTS[@]}"; do
        echo "==== Processing $HOST ===="

        ssh -o StrictHostKeyChecking=no "$USER@$HOST" "sudo sh -c 'echo > /var/log/syslog'"
        # ssh -o StrictHostKeyChecking=no "$USER@$HOST" "sudo sh -c 'echo > /var/log/couchdb/couch.log'"

        scp -o StrictHostKeyChecking=no "$SCRIPT_NAME" "$USER@$HOST:/tmp/$SCRIPT_NAME"
        ssh -o StrictHostKeyChecking=no "$USER@$HOST" "sudo bash /tmp/$SCRIPT_NAME"

        echo "==== Done with $HOST ===="
    done
}

get_hosts "$@"
generate_install_script
run_install_on_hosts
rm -f "$SCRIPT_NAME"
