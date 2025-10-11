const axios = require("axios");

const CREDS = "script-user:ug34AD_1TfYajg-23_aMeQt"

const BLACKLIST = ["CIGNITI", "India test"];

const getIPSCustomer = async () => {
    try {
        const filter = [{ "id": "purpose", "value": "Development" }, { "id": "assignedLocation", "value": "AirFi Office - India" }]
        const base64Filter = Buffer.from(JSON.stringify(filter)).toString('base64');;
        const url = `https://${CREDS}@airfi-disco.herokuapp.com/api/devices?hideOffline=false&onlyProduction=false&hideWithoutProxy=false&onOnlyUnmatchingCustomers=false&sorts=W3siZGVzYyI6dHJ1ZSwiaWQiOiJsYXN0U2VlblRpbWVzdGFtcCJ9XQ==&filters=${base64Filter}&pagination=false`
        const response = (await axios.get(url).then(response => response.data).catch(console.error)).rows.filter(row => row.nickname).map(row => { return { nickname: row.nickname, serial: row.serial } }).filter(deivce => !BLACKLIST.includes(deivce.nickname))
        return response;
    }
    catch (e) {
        console.log(e.message)
    }
}

const lastSync = async (ip) => {
    const url = `https://${CREDS}@airfi-disco.herokuapp.com/api/device/${ip}`
    const response = (await axios.get(url).then(response => response.data));
    return response.contentSyncAttemptTimestamp;
}



async function main() {
    const test = await getIPSCustomer()
    for (const device of test) {
        const lastSyncTime = await lastSync(device.serial)
        console.log(`"${device.serial}", // ${device.nickname} ${lastSyncTime}`)
    }
}

main();
