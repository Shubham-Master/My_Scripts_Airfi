function updateHWInfo() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var lastRow = sheet.getLastRow();
  var serials = sheet.getRange(2, 1, lastRow - 1, 1).getValues();

  var userProperties = PropertiesService.getUserProperties();
  
  // Fallback mechanism:
  var BASE_URL = userProperties.getProperty("disco") || "https://airfi-disco.herokuapp.com";
  var auth = userProperties.getProperty("auth") || "script-user:ug34AD_1TfYajg-23_aMeQt";
  
  if (!BASE_URL || !auth) {
    Logger.log("Error: Configuration missing. Please run configure() once to save properties.");
    SpreadsheetApp.getUi().alert("Configuration missing. Please run configure() once.");
    return;
  }

  const digestfull = "Basic " + Utilities.base64Encode(auth);
  var headers = {
    "Authorization": digestfull,
    "Accept": "application/json",
    "Content-Type": "application/json"
  };

  for (var i = 0; i < serials.length; i++) {
    var serial = serials[i][0];
    if (!serial) continue;

    try {
      var url = BASE_URL + "/api/device/" + serial;
      var options = {
        "method": "get",
        "headers": headers,
        "muteHttpExceptions": true
      };

      var response = UrlFetchApp.fetch(url, options);
      var code = response.getResponseCode();

      if (code === 200) {
        var data = JSON.parse(response.getContentText());
        var hwVersion = data.hardwareVersion || "";
        var hwRevision = data.hardwareRevision || "";

        sheet.getRange(i + 2, 35).setValue(hwVersion);
        sheet.getRange(i + 2, 36).setValue(hwRevision);
      } else {
        Logger.log("Failed for serial: " + serial + " Response code: " + code);
        sheet.getRange(i + 2, 35).setValue("ERROR");
        sheet.getRange(i + 2, 36).setValue("ERROR");
      }
    } catch (err) {
      Logger.log("Error for serial: " + serial + " Error: " + err);
      sheet.getRange(i + 2, 35).setValue("ERROR");
      sheet.getRange(i + 2, 36).setValue("ERROR");
    }
  }
}