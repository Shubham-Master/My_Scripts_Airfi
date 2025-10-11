const FW = "7373-moon"
const IPS = [
    "10.0.6.177", // Alister
    "10.0.6.203", // Bala
    "10.0.3.63", // Pramitha
    "10.0.4.26", // Sunil Joshi
    "10.0.4.70", // Bharat
    "10.0.9.37", // Shubham Kumar
    "10.0.4.160", // Pramitha
    "10.0.8.114", // Sanjay Herle
    "10.0.9.158", // Shubham Kumar
    "10.0.8.17", // Ranjan
    "10.0.7.140", // Shubham Singh
    "10.0.6.56", // Mukul
    "10.0.9.24", // Ranjan
    "10.0.10.251", // Sunil Joshi
    "10.0.8.207", // Bala
    "10.0.6.181", // RK
    "10.0.4.137", // Suhas
    "10.0.6.69", // Malcolm Box II
    "10.0.8.60", // Malcolm
    "10.0.9.62", // Shweta
    "10.0.9.117", // Pratheek
    "10.0.7.17", // Aatif
    "10.0.8.156", // GM
    "10.0.8.66", // Ami
    "10.0.8.247", // Ami
    "10.0.9.176", // Mayank
    "10.0.3.255", // RM Moon-2
    "10.0.1.153", // RM Moon-1
    "10.0.7.23", // Janushi
    "10.0.3.16", // Surbhi
    "10.0.6.248", // Aatif
    "10.0.4.233", // Pramitha
    "10.0.2.248", // Sonam
    "10.0.4.217", // RM Moon-7
    "10.0.9.9", // Bala
    "10.0.4.32", // Sonam
    "10.0.3.57", // Jatin
    "10.0.4.2", // Surbhi
    "10.0.3.196", // Dharmesh
    "10.0.3.44", // Pratheek
    "10.0.3.76", // Tanveer's
    "10.0.5.65", // Ranjan
    "10.0.9.100", // RK
    "10.0.1.181", // Mayank
    "10.0.1.236", // Shubham Kumar
    "10.0.9.43", // Milind
    "10.0.3.59", // Jatin
    "10.0.3.82", // Jatin
    "10.0.8.2", // Bala
    "10.0.8.25", // toRM-NLreturn
]
const host = "https://airfi-disco.herokuapp.com";
const username = "box-firmware"
const password = "sun-reactive-collaboration"
const cred = `Basic ${Buffer.from(username + ":" + password).toString('base64')}`
const axios = require('axios');

async function assignNonProxyBoxes(serial) {
    const url = `${host}/api/device/${serial}`
    const payload = { "assignedFirmware": FW }
    await axios.patch(url, payload, {
        headers: {
            "Authorization": cred
        }
    }).then(resp => resp.data).catch(err => console.error(err));
    console.log(`[+] Assigned new FW to ${serial}`)
};


async function main() {
    let chunkSize = 100;
    let res = [];
    for (let i in IPS) {
        const box = IPS[i];
        res.push(assignNonProxyBoxes(box));
        if (i % chunkSize === 0) {
            await Promise.all(res);
            res = [];
        }
    }
    await Promise.all(res);
    return "done";
}


main().then(console.log).catch(console.error)