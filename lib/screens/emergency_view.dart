<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>Emergency Info | VitaLink</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0" />

<style>

:root{
--bg:#000000;
--card:#0c0c0c;
--text:#ffffff;
--muted:#aaaaaa;
--divider:#1e1e1e;
--alert-bg:#2a0000;
--alert-border:#e53935;
}

body.light{
--bg:#f5f5f5;
--card:#ffffff;
--text:#111;
--muted:#555;
--divider:#ddd;
--alert-bg:#ffeaea;
--alert-border:#e53935;
}

body.ems{
--text:#ffffff;
--muted:#cccccc;
--divider:#333;
}

body{
margin:0;
background:var(--bg);
color:var(--text);
font-family:system-ui,-apple-system,BlinkMacSystemFont,sans-serif;
display:flex;
justify-content:center;
padding:20px;
}

.card{
width:100%;
max-width:520px;
padding:28px;
border-radius:18px;
background:var(--card);
box-shadow:0 20px 60px rgba(0,0,0,0.6);
position:relative;
}

.logo{text-align:center;margin-bottom:20px;}
.logo img{height:120px;}

h1{color:#e53935;text-align:center;margin-bottom:18px;}

.section{
margin-bottom:18px;
border-top:1px solid var(--divider);
padding-top:14px;
}

.label{
font-size:13px;
color:var(--muted);
text-transform:uppercase;
}

.value{
font-size:17px;
margin-top:4px;
line-height:1.4;
}

body.ems .value{
font-size:20px;
font-weight:600;
}

.alert{
background:var(--alert-bg);
border-left:5px solid var(--alert-border);
padding:12px;
border-radius:8px;
}

.hint{
margin-top:18px;
font-size:14px;
color:var(--muted);
text-align:center;
}

.toggle-wrap{
position:absolute;
top:14px;
right:14px;
display:flex;
gap:6px;
}

.theme-toggle{
background:none;
border:1px solid var(--divider);
color:var(--text);
padding:6px 12px;
border-radius:999px;
font-size:12px;
cursor:pointer;
}

</style>
</head>

<body>

<div class="card" id="app">

<div class="toggle-wrap">
<button class="theme-toggle" onclick="toggleTheme()">Light</button>
<button class="theme-toggle" onclick="toggleEMS()">EMS</button>
</div>

<div class="logo">
<img src="/images/vitalink-logo.png" />
</div>

<h1>Emergency Session Expired</h1>

<div class="hint">Scan QR Code to access emergency data</div>

</div>

<script>

function toggleTheme(){
document.body.classList.toggle("light");
}

function toggleEMS(){
document.body.classList.toggle("ems");
}

(function(){

const params = new URLSearchParams(window.location.search);
const raw = params.get("data");
if(!raw) return;

const normalized = raw.replace(/-/g,'+').replace(/_/g,'/');

let decoded;
try{
decoded = JSON.parse(atob(normalized));
}catch{
return;
}

const app = document.getElementById("app");

app.innerHTML = `

<div class="toggle-wrap">
<button class="theme-toggle" onclick="toggleTheme()">Light</button>
<button class="theme-toggle" onclick="toggleEMS()">EMS</button>
</div>

<div class="logo">
<img src="/images/vitalink-logo.png" />
</div>

<h1>Emergency Information</h1>

<div class="section">
<div class="label">Name</div>
<div class="value">${decoded.name || "N/A"}</div>
</div>

<div class="section">
<div class="label">DOB</div>
<div class="value">${decoded.dob || "N/A"}</div>
</div>

<div class="section alert">
<div class="label">Allergies</div>
<div class="value">${decoded.allergies || "None reported"}</div>
</div>

<div class="section alert">
<div class="label">Conditions</div>
<div class="value">${decoded.conditions || "None reported"}</div>
</div>

<div class="section">
<div class="label">Implants</div>
<div class="value">${decoded.implants || "None reported"}</div>
</div>

<div class="section">
<div class="label">Procedures</div>
<div class="value">${decoded.procedures || "None reported"}</div>
</div>

<div class="section">
<div class="label">Blood Type</div>
<div class="value">${decoded.bloodType || "Unknown"}</div>
</div>

<div class="section">
<div class="label">Organ Donor</div>
<div class="value">${decoded.organDonor ? "YES" : "NO"}</div>
</div>

<div class="section">
<div class="label">Emergency Contact</div>
<div class="value">${decoded.emergencyContactName || "N/A"}</div>
</div>

<div class="section">
<div class="label">Phone</div>
<div class="value">${decoded.emergencyContactPhone || "N/A"}</div>
</div>

${
decoded.meds?.length
? `
<div class="section">
<div class="label">Medications</div>
<div class="value">
${decoded.meds.map(m =>
`${m.name || ""}${m.dose ? " – " + m.dose : ""}${m.frequency ? " (" + m.frequency + ")" : ""}`
).join("<br>")}
</div>
</div>
`
: ""
}

${
decoded.providers?.length
? `
<div class="section">
<div class="label">Doctors</div>
<div class="value">
${decoded.providers.map(d =>
`${d.name || ""}${d.phone ? " – " + d.phone : ""}`
).join("<br>")}
</div>
</div>
`
: ""
}

<div class="hint">
Session ends when page is closed
</div>

`;

})();

</script>

</body>
</html>