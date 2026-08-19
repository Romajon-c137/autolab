export type ApplicationFormState = {
  applicant: string;
  inn: string;
  phone: string;
  vehicleName: string;
  plateNumber: string;
  year: string;
  vin: string;
};

export function buildApplicationDocument(form: ApplicationFormState, signatureData: string) {
  const plate = splitPlateNumber(form.plateNumber);
  const date = new Date();
  const day = new Intl.DateTimeFormat("ru-RU", { day: "2-digit" }).format(date);
  const month = new Intl.DateTimeFormat("ru-RU", { month: "long" }).format(date);
  const year = new Intl.DateTimeFormat("ru-RU", { year: "numeric" }).format(date);
  const value = (text: string) => escapeHtml(text);

  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  * { box-sizing: border-box; }
  html, body { margin:0; padding:0; background:#fff; overflow:hidden; }
  body { font-family:"Times New Roman", Times, serif; color:#000; }
  .page {
    width:210mm; height:297mm; margin:0; background:#fff; overflow:hidden;
    padding:15mm 12.5mm 20mm 20mm;
    font-size:11pt; line-height:1.08;
  }
  .header { text-align:center; font-family:Arial, Helvetica, sans-serif; }
  .org { font-size:14pt; font-weight:700; text-decoration:underline; margin:0; }
  .org-note { font-size:13pt; margin:0 0 4mm; }
  .title { font-size:14pt; font-weight:700; margin:0; }
  .subtitle { font-size:14pt; font-weight:700; margin:0 0 2.5mm; line-height:1.15; }
  .line-row { display:flex; align-items:flex-end; width:100%; min-height:5.3mm; }
  .label { white-space:nowrap; }
  .fill {
    flex:1 1 auto; min-width:10mm; height:5.1mm; border:0; border-bottom:.28mm solid #000;
    background:transparent; padding:0 1.2mm .25mm; margin:0; outline:none;
    font:11pt "Times New Roman", Times, serif; line-height:1.05; border-radius:0; appearance:none; -webkit-appearance:none;
  }
  .hand {
    color:#21327f;
    font-family:"Segoe Print","Bradley Hand","Comic Sans MS",cursive;
    font-size:13.5pt;
    font-weight:600;
    line-height:1;
  }
  .first-fill {
    flex:1 1 auto; height:5.1mm; border-bottom:.28mm solid #000;
    display:flex; align-items:flex-end; justify-content:space-between; gap:8mm;
    padding:0 1.2mm .25mm;
  }
  .first-fill span { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .fill.small { flex:0 0 auto; }
  .fill.code { width:43mm; }
  .fill.number { width:35mm; }
  .fill.series { width:auto; }
  .fill.year { width:auto; }
  .fill.phone { width:52mm; }
  .fill.email { width:auto; }
  .caption { text-align:center; margin:-.3mm 0 .7mm; }
  .section { margin-top:.7mm; }
  .section-gap { margin-top:2.1mm; }
  .rule { border-top:.28mm solid #000; margin:2mm 0 3mm; }
  .mp { margin:1.8mm 0 1mm; }
  .delegate-caption { text-align:center; margin:.4mm 0 0; }
  .delegate-grid {
    display:grid; grid-template-columns:31mm 25mm 56mm 43mm; column-gap:5mm;
    align-items:end; margin-top:1.5mm;
  }
  .delegate-grid .field-wrap { text-align:left; min-width:0; }
  .delegate-grid .fill { width:100%; }
  .delegate-grid .under { text-align:center; margin-top:.9mm; line-height:1.05; }
  .inspection-grid { display:grid; grid-template-columns:40mm 57mm 1fr; gap:4mm; align-items:end; }
  .inspection-grid > div { min-width:0; }
  .inspection-grid .fill { width:100%; }
  .under-center { text-align:center; margin-top:.6mm; }
  .result-row { display:grid; grid-template-columns:88mm 1fr; column-gap:4mm; align-items:center; margin-top:1.6mm; }
  .ticket-box {
    height:10.7mm; border:.28mm solid #000; display:flex; align-items:center; gap:1mm; padding:1.2mm 1.6mm;
  }
  .ticket-box .prefix { white-space:nowrap; }
  .ticket-box .boxfill { border:0; border-bottom:.28mm solid #000; height:5.5mm; font:11pt "Times New Roman"; padding:0 1mm; outline:none; background:transparent; }
  .ticket-box .num { width:30mm; }
  .ticket-box .day { width:10mm; text-align:center; }
  .ticket-box .month { width:20mm; text-align:center; }
  .ticket-box .yy { width:12mm; text-align:center; }
  .sign-grid { display:grid; grid-template-columns:34mm 49mm 1fr; column-gap:10mm; margin-top:3.3mm; align-items:end; }
  .sign-grid > div { min-width:0; }
  .sign-grid .fill { width:100%; }
  .sign-grid .under { text-align:center; margin-top:.7mm; }
  .manager { display:grid; grid-template-columns:47mm 47mm 1fr; column-gap:5mm; align-items:end; margin-top:4.5mm; }
  .manager-label { line-height:1.25; }
  .manager > div { min-width:0; }
  .manager .fill { width:100%; }
  .manager .under { text-align:center; margin-top:.7mm; }
  .signature-cell { position:relative; height:7mm; border-bottom:.28mm solid #000; }
  .signature-cell img { position:absolute; left:0; bottom:-1.4mm; width:100%; max-height:16mm; object-fit:contain; }
  .seal-date { display:flex; align-items:flex-end; margin-top:5.6mm; gap:1.3mm; }
  .seal-date .quote { white-space:nowrap; }
  .seal-day { width:13mm; }
  .seal-month { width:38mm; }
  @media print {
    @page { size:A4 portrait; margin:0; }
    .page { width:210mm; height:297mm; margin:0; overflow:hidden; }
  }
</style>
</head>
<body>
<main class="page">
  <header class="header">
    <p class="org">ГП ЦТН ГУОБДД МВД КР, Г.Ош ул.А.Навои 2а</p>
    <p class="org-note">наименование диагностического центра, адрес</p>
    <p class="title">ЗАЯВКА</p>
    <p class="subtitle">на проведение технического осмотра транспортного<br>средства</p>
  </header>
  <section>
    <div class="line-row"><span class="label">1.&nbsp;</span><div class="first-fill hand"><span>${value(form.applicant)}</span><span>${value(form.inn)}</span></div></div>
    <div class="caption">наименование эксплуатанта ТС, ИНН или номер регистрационного</div>
    <div class="line-row"><input class="fill" readonly value=""></div>
    <div class="caption">документа индивидуального предпринимателя, свидетельства</div>
    <div class="line-row"><input class="fill" readonly value=""></div>
    <div class="caption">о государственной регистрации, ФИО</div>
    <div class="line-row"><span class="label">юридический адрес&nbsp;</span><input class="fill" readonly value=""></div>
    <div class="line-row">
      <span class="label">телефон&nbsp;</span><input class="fill small phone hand" readonly value="${value(form.phone)}">
      <span class="label">&nbsp;e-mail&nbsp;</span><input class="fill email" readonly value="">
    </div>
  </section>
  <section class="section">
    <div>2. Прошу провести технический осмотр (далее - ТО)</div>
    <div class="line-row"><span class="label">транспортного средства:&nbsp;</span><input class="fill hand" readonly value="${value(form.vehicleName)}"></div>
    <div class="caption">(наименование, марка машины)</div>
    <div class="line-row"><input class="fill" readonly value=""></div>
    <div class="section-gap">Государственный регистрационный знак:</div>
    <div class="line-row">
      <span class="label">код&nbsp;</span><input class="fill small code hand" readonly value="${value(plate.code)}">
      <span class="label">&nbsp;номер&nbsp;</span><input class="fill small number hand" readonly value="${value(plate.number)}">
      <span class="label">&nbsp;серия</span><input class="fill series hand" readonly value="${value(plate.series)}">
    </div>
    <div class="line-row"><span class="label">Год выпуска&nbsp;</span><input class="fill year hand" readonly value="${value(form.year)}"></div>
    <div>Заводской номер, идентификационный номер (VIN или PIN);</div>
    <div class="line-row"><span class="label">номер двигателя&nbsp;</span><input class="fill hand" readonly value="${value(form.vin)}"></div>
  </section>
  <section class="section">
    <div>3. Документы, подтверждающие право собственности</div>
    <div class="line-row"><input class="fill" readonly value=""></div>
  </section>
  <section class="section">
    <div class="line-row"><span class="label">4. ТО машины доверяется провести (при необходимости):&nbsp;</span><input class="fill" readonly value=""></div>
    <div class="line-row"><input class="fill" readonly value=""></div>
    <div class="delegate-caption">(фамилия, имя, отчество (при наличии), должность, наименование</div>
    <div class="line-row"><input class="fill" readonly value=""></div>
    <div class="delegate-caption">документа, удостоверяющего личность, серия, номер, когда и кем выдан)</div>
    <div class="delegate-grid">
      <div class="field-wrap"><input class="fill" readonly value=""><div class="under">(контактный<br>телефон)</div></div>
      <div class="field-wrap"><div class="signature-cell">${signatureData ? `<img src="${signatureData}" alt="">` : ""}</div><div class="under">(подпись)</div></div>
      <div class="field-wrap"><input class="fill" readonly value=""><div class="under">(фамилия, инициалы<br>руководителя организации)</div></div>
      <div class="field-wrap"><input class="fill" readonly value=""><div class="under">(дата, месяц, год)</div></div>
    </div>
    <div class="rule"></div>
    <div class="mp">М.П.</div>
  </section>
  <section class="section">
    <div class="inspection-grid">
      <div>5. ТО машины провел:</div>
      <div><input class="fill" readonly value=""><div class="under-center">подпись</div></div>
      <div><input class="fill" readonly value=""><div class="under-center">(фамилия, инициалы)</div></div>
    </div>
  </section>
  <section class="section-gap">
    <div>6. По результатам ТО машины получены:</div>
    <div class="result-row">
      <div class="ticket-box">
        <span class="prefix">№</span><input class="boxfill num" readonly value="">
        <span>"</span><input class="boxfill day" readonly value=""><span>"</span>
        <input class="boxfill month" readonly value="">
        <input class="boxfill yy" readonly value="${value(year)}"><span>г.</span>
      </div>
      <div>Диагностическая карта ТО (номер и дата);</div>
    </div>
    <div class="result-row">
      <div class="ticket-box">
        <span class="prefix">№</span><input class="boxfill num" readonly value="">
        <span>"</span><input class="boxfill day" readonly value=""><span>"</span>
        <input class="boxfill month" readonly value="">
        <input class="boxfill yy" readonly value="${value(year)}"><span>г.</span>
      </div>
      <div>Талон о прохождении ТО (номер и дата)</div>
    </div>
    <div class="sign-grid">
      <div><input class="fill" readonly value=""><div class="under">(должность)</div></div>
      <div><input class="fill" readonly value=""><div class="under">(подпись)</div></div>
      <div><input class="fill" readonly value=""><div class="under">(фамилия, инициалы)</div></div>
    </div>
  </section>
  <section class="manager">
    <div class="manager-label">7. Руководитель<br>организации<br>(эксплуатант)</div>
    <div><input class="fill" readonly value=""><div class="under">подпись</div></div>
    <div><input class="fill" readonly value=""><div class="under">инициалы, фамилия</div></div>
  </section>
  <section class="seal-date">
    <span class="quote">Печать<br>"</span><input class="fill small seal-day hand" readonly value="${value(day)}"><span>"</span>
    <input class="fill small seal-month hand" readonly value="${value(month)}"><span>${value(year)}г.</span>
  </section>
</main>
<script>
  const page = document.querySelector('.page');
  function fitPage() {
    if (!page) return;
    const scale = window.innerWidth / page.offsetWidth;
    page.style.transformOrigin = 'top left';
    page.style.transform = 'scale(' + scale + ')';
    document.body.style.width = window.innerWidth + 'px';
    document.body.style.height = (page.offsetHeight * scale) + 'px';
  }
  window.addEventListener('resize', fitPage);
  fitPage();
</script>
</body>
</html>`;
}

function splitPlateNumber(value: string) {
  const compact = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  const match = compact.match(/^(\d{2}KG)(\d+)([A-Z]+)$/);
  if (!match) {
    return { code: "", number: compact, series: "" };
  }
  return {
    code: match[1],
    number: match[2],
    series: match[3],
  };
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
