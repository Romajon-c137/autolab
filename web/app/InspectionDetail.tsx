"use client";

import { useState } from "react";
import { Download, ExternalLink } from "lucide-react";
import { Inspection, formatDate, formatPhotoDate, operationLabel, pdfFileName, photoLabels } from "./lib";

function printDocumentPdf(url: string) {
  const win = window.open("about:blank", "_blank");
  if (!win) {
    window.open(url, "_blank");
    return;
  }
  const safeUrl = url.replace(/"/g, "%22");
  win.document.write(
    '<!doctype html><html><head><title>Печать</title></head>' +
      '<body style="margin:0;padding:0">' +
      '<embed id="doc" src="' +
      safeUrl +
      '" type="application/pdf" style="width:100vw;height:100vh">' +
      "</body></html>"
  );
  win.document.close();
  win.addEventListener("afterprint", () => win.close());
  win.addEventListener("load", () => {
    win.focus();
    setTimeout(() => win.print(), 600);
  });
}

export function InspectionDetail({ inspection }: { inspection: Inspection }) {
  const [activePhoto, setActivePhoto] = useState<null | { src: string; label: string }>(null);
  const pdfName = pdfFileName(inspection);

  return (
    <section className="detail-grid">
      <div className="detail-sidebar">
        <table className="detail-table">
          <tbody>
            <tr>
              <th>Название</th>
              <td>{inspection.title || "-"}</td>
            </tr>
            <tr>
              <th>Тип операции</th>
              <td>{operationLabel(inspection)}</td>
            </tr>
            <tr>
              <th>Марка / модель</th>
              <td>{inspection.brand || "-"}</td>
            </tr>
            <tr>
              <th>Категория</th>
              <td>{inspection.vehicle_category || "M1"}</td>
            </tr>
            <tr>
              <th>VIN</th>
              <td className="detail-vin-value">{inspection.vin || "-"}</td>
            </tr>
            <tr>
              <th>Дата</th>
              <td className="detail-date-value">{formatDate(inspection.created_at)}</td>
            </tr>
            <tr>
              <th>Оператор</th>
              <td>{inspection.created_by?.login ?? "-"}</td>
            </tr>
          </tbody>
        </table>
        {inspection.document_pdf ? (
          <section className="document-panel">
            <div className="document-panel-header">
              <h3>Документ</h3>
              <div className="document-actions">
                <button
                  className="icon-button print-btn"
                  type="button"
                  onClick={() => inspection.document_pdf && printDocumentPdf(inspection.document_pdf)}
                  title="Печать PDF"
                  aria-label="Печать PDF"
                >
                  Печать
                </button>
                <a
                  href={inspection.document_pdf}
                  target="_blank"
                  rel="noreferrer"
                  className="icon-button"
                  title="Предпросмотр"
                  aria-label="Предпросмотр"
                >
                  <ExternalLink aria-hidden="true" />
                </a>
                <a
                  href={inspection.document_pdf}
                  download={pdfName}
                  className="icon-button"
                  title="Скачать PDF"
                  aria-label="Скачать PDF"
                >
                  <Download aria-hidden="true" />
                </a>
              </div>
            </div>
            <div className="document-preview-card">
              <div className="document-preview-page">
                <div className="document-preview-lines">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
                <div className="document-preview-table">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
              </div>
              <div>
                <strong>PDF документ готов</strong>
                <p>Файл сохранен вместе с осмотром.</p>
              </div>
            </div>
          </section>
        ) : null}
        {inspection.application_pdf ? (
          <section className="document-panel">
            <div className="document-panel-header">
              <h3>Заявка клиента</h3>
              <div className="document-actions">
                <button
                  className="icon-button print-btn"
                  type="button"
                  onClick={() => inspection.application_pdf && printDocumentPdf(inspection.application_pdf)}
                  title="Печать заявки"
                  aria-label="Печать заявки"
                >
                  Печать
                </button>
                <a
                  href={inspection.application_pdf}
                  target="_blank"
                  rel="noreferrer"
                  className="icon-button"
                  title="Предпросмотр"
                  aria-label="Предпросмотр"
                >
                  <ExternalLink aria-hidden="true" />
                </a>
                <a
                  href={inspection.application_pdf}
                  download={`zayavka-${pdfName}`}
                  className="icon-button"
                  title="Скачать заявку"
                  aria-label="Скачать заявку"
                >
                  <Download aria-hidden="true" />
                </a>
              </div>
            </div>
            <div className="document-preview-card">
              <div className="document-preview-page">
                <div className="document-preview-lines">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
                <div className="document-preview-table">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
              </div>
              <div>
                <strong>PDF заявки готов</strong>
                <p>Файл прикреплен по совпадению VIN.</p>
              </div>
            </div>
          </section>
        ) : null}
      </div>
      <div className="photo-grid">
        {Object.entries(photoLabels).map(([key, label]) => (
          <div className="photo-card" key={key}>
            {inspection.photos[key] ? (
              <button
                className="photo-open-button"
                type="button"
                onClick={() => setActivePhoto({ src: inspection.photos[key], label })}
              >
                <img src={inspection.photos[key]} alt={label} />
              </button>
            ) : (
              <div style={{ aspectRatio: "4 / 3" }} />
            )}
            <span>
              <strong>{label}</strong>
              {formatPhotoDate(inspection, key)}
            </span>
          </div>
        ))}
      </div>
      {activePhoto ? (
        <div className="photo-modal" role="dialog" aria-modal="true" onClick={() => setActivePhoto(null)}>
          <div className="photo-modal-content" onClick={(event) => event.stopPropagation()}>
            <button className="photo-modal-close" type="button" onClick={() => setActivePhoto(null)}>
              Закрыть
            </button>
            <img src={activePhoto.src} alt={activePhoto.label} />
            <span>{activePhoto.label}</span>
          </div>
        </div>
      ) : null}
    </section>
  );
}
