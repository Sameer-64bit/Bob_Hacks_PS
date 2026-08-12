import type { Lecture, TargetLanguage } from '../types';
import { getLanguageInfo } from '../types';
import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';

export async function exportLectureNotesToPDF(
  lecture: Lecture,
  targetLang: TargetLanguage,
  elementId: string
): Promise<void> {
  const element = document.getElementById(elementId);
  
  if (!element) {
    console.warn(`Element #${elementId} not currently visible in DOM. Triggering native print fallback...`);
    window.print();
    return;
  }

  try {
    const canvas = await html2canvas(element, {
      scale: 2,
      useCORS: true,
      backgroundColor: '#090d16',
      logging: false,
      ignoreElements: (el) => el.classList.contains('no-print')
    });

    const imgData = canvas.toDataURL('image/png');
    const pdf = new jsPDF({
      orientation: 'portrait',
      unit: 'mm',
      format: 'a4'
    });

    const imgWidth = 210; // A4 width in mm
    const pageHeight = 297; // A4 height in mm
    const imgHeight = (canvas.height * imgWidth) / canvas.width;
    let heightLeft = imgHeight;
    let position = 0;

    pdf.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
    heightLeft -= pageHeight;

    while (heightLeft > 0) {
      position = heightLeft - imgHeight;
      pdf.addPage();
      pdf.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
      heightLeft -= pageHeight;
    }

    const langName = getLanguageInfo(targetLang).name;
    const safeTitle = lecture.title.replace(/[^a-zA-Z0-9_-]/g, '_');
    pdf.save(`SmartClassroom_${safeTitle}_${langName}_Notes.pdf`);
  } catch (err) {
    console.error('html2canvas PDF generation error, falling back to window.print():', err);
    window.print();
  }
}

export async function exportTeacherBoardSlidesToPDF(lecture: Lecture): Promise<void> {
  if (!lecture.pages.length) return;

  const exportRoot = document.createElement('div');
  exportRoot.style.position = 'fixed';
  exportRoot.style.left = '-100000px';
  exportRoot.style.top = '0';
  exportRoot.style.width = '1120px';
  exportRoot.style.backgroundColor = '#0f172a';
  exportRoot.style.pointerEvents = 'none';
  exportRoot.style.zIndex = '-1';
  document.body.appendChild(exportRoot);

  try {
    const pdf = new jsPDF({
      orientation: 'landscape',
      unit: 'mm',
      format: 'a4'
    });

    for (const [index, page] of lecture.pages.entries()) {
      const board = document.createElement('div');
      board.style.width = '1120px';
      board.style.height = '700px';
      board.style.display = 'flex';
      board.style.alignItems = 'center';
      board.style.justifyContent = 'center';
      board.style.overflow = 'hidden';
      board.style.backgroundColor = '#0f172a';
      board.innerHTML = page.boardImageSvg;

      const svg = board.querySelector('svg');
      if (svg) {
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', '100%');
        svg.style.display = 'block';
        svg.style.maxWidth = '100%';
        svg.style.maxHeight = '100%';
      }

      exportRoot.appendChild(board);

      const canvas = await html2canvas(board, {
        scale: 2,
        useCORS: true,
        backgroundColor: '#0f172a',
        logging: false
      });

      if (index > 0) pdf.addPage();

      const pageWidth = 297;
      const pageHeight = 210;
      const margin = 8;
      const imageWidth = pageWidth - margin * 2;
      const imageHeight = (canvas.height * imageWidth) / canvas.width;
      const y = Math.max(margin, (pageHeight - imageHeight) / 2);

      pdf.addImage(canvas.toDataURL('image/png'), 'PNG', margin, y, imageWidth, imageHeight);
      board.remove();
    }

    const safeTitle = lecture.title.replace(/[^a-zA-Z0-9_-]/g, '_');
    pdf.save(`SmartClassroom_${safeTitle}_Teacher_Board_Slides.pdf`);
  } catch (err) {
    console.error('Teacher board PDF generation error:', err);
  } finally {
    exportRoot.remove();
  }
}
