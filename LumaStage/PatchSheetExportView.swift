import SwiftUI

#if os(visionOS)
/// Presents the current look's DMX patch sheet (the load-in paperwork) and exports it as a PDF — the
/// "design in the headset, hand a sheet to the technician, patch it on a real console" bridge. The pure
/// allocation + summary live in `LightingPatchSheet` / `DMXPatchPlanner` (smoke-tested); this view only
/// renders and shares them.
struct PatchSheetExportView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sheet = appModel.patchSheet
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryRow(sheet)
                    sheetTable(sheet)
                    Text("每盞燈具佔用 4 個 DMX 通道（調光、紅、綠、藍），自位址 1 起依序配接，滿 512 後進入下一個 Universe。")
                        .font(.footnote)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                }
                .padding(28)
            }
            .navigationTitle("DMX 配接表")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: exportedPDF(for: sheet)) {
                        Label("匯出 PDF", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 580)
    }

    private func summaryRow(_ sheet: LightingPatchSheet) -> some View {
        HStack(spacing: 14) {
            summaryChip("燈具", "\(sheet.fixtureCount)", systemImage: "lightbulb.fill")
            summaryChip("Universe", "\(sheet.universeCount)", systemImage: "rectangle.3.group")
            summaryChip("DMX 通道", "\(sheet.channelCount)", systemImage: "slider.horizontal.3")
            Spacer()
        }
    }

    private func summaryChip(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(LumaStageDesign.coolBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.weight(.bold)).foregroundStyle(LumaStageDesign.textPrimary)
                Text(title).font(.caption).foregroundStyle(LumaStageDesign.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .lumaNativeGlass(radius: LumaStageDesign.surfaceRadius)
    }

    private func sheetTable(_ sheet: LightingPatchSheet) -> some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(sheet.rows) { row in
                Divider().overlay(LumaStageDesign.hairline)
                dataRow(row)
            }
        }
        .padding(.vertical, 6)
        .lumaNativeGlass(radius: LumaStageDesign.surfaceRadius)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            cell("燈號", width: 56, weight: .bold)
            cell("名稱", width: 150, weight: .bold, alignment: .leading)
            cell("類型", width: 130, weight: .bold, alignment: .leading)
            cell("Universe", width: 90, weight: .bold)
            cell("位址", width: 64, weight: .bold)
            cell("通道", width: 80, weight: .bold)
            cell("顏色", width: 100, weight: .bold, alignment: .leading)
        }
        .padding(.vertical, 8)
        .foregroundStyle(LumaStageDesign.textPrimary)
    }

    private func dataRow(_ row: LightingPatchSheet.Row) -> some View {
        let rgb = RGBComponents(hex: row.colorHex) ?? .white
        return HStack(spacing: 0) {
            cell("\(row.number)", width: 56, weight: .semibold)
            cell(row.name, width: 150, alignment: .leading)
            cell(row.fixtureType, width: 130, alignment: .leading)
            cell("U\(row.universe)", width: 90)
            cell("\(row.address)", width: 64, monospaced: true)
            cell(row.channelSpan, width: 80, monospaced: true)
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(LumaStageDesign.hairline))
                Text(row.colorHex).font(.caption.monospaced())
            }
            .frame(width: 100, alignment: .leading)
            .foregroundStyle(LumaStageDesign.textSecondary)
        }
        .padding(.vertical, 8)
    }

    private func cell(_ text: String, width: CGFloat, weight: Font.Weight = .regular,
                      alignment: Alignment = .center, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? .callout.monospaced() : .callout.weight(weight))
            .foregroundStyle(LumaStageDesign.textPrimary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 6)
    }

    /// Renders the printable document to a single-page PDF in the temp directory and returns its URL.
    /// ImageRenderer → CGContext(PDF) is the standard SwiftUI-view-to-PDF recipe; it runs on the main
    /// actor (this view's context), so it's safe to call from `body`.
    private func exportedPDF(for sheet: LightingPatchSheet) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaStage-配接表.pdf")
        let renderer = ImageRenderer(content: PatchSheetDocument(sheet: sheet))
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            pdf.beginPDFPage(nil)
            renderInContext(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return url
    }
}

/// A light-on-white, print-friendly rendering of the patch sheet — what the exported PDF shows. Kept
/// separate from the in-app (glass) presentation so the PDF reads on paper.
private struct PatchSheetDocument: View {
    let sheet: LightingPatchSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LumaStage 燈光配接表").font(.title2.weight(.bold))
                Text(sheet.lookName).font(.headline).foregroundStyle(.secondary)
                Text("\(sheet.fixtureCount) 盞燈具 · \(sheet.universeCount) 個 Universe · \(sheet.channelCount) 個 DMX 通道")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                docRow("燈", "名稱", "類型", "Univ.", "位址", "通道", "顏色", bold: true)
                ForEach(sheet.rows) { row in
                    Divider()
                    docRow("\(row.number)", row.name, row.fixtureType,
                           "U\(row.universe)", "\(row.address)", row.channelSpan, row.colorHex)
                }
            }
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.4)))
        }
        .padding(36)
        .frame(width: 792)   // US Letter landscape-ish width at 72dpi
        .background(.white)
        .foregroundStyle(.black)
    }

    private func docRow(_ a: String, _ b: String, _ c: String, _ d: String,
                        _ e: String, _ f: String, _ g: String, bold: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(a).frame(width: 40, alignment: .center)
            Text(b).frame(width: 160, alignment: .leading)
            Text(c).frame(width: 140, alignment: .leading)
            Text(d).frame(width: 70, alignment: .center)
            Text(e).frame(width: 60, alignment: .center)
            Text(f).frame(width: 70, alignment: .center)
            Text(g).frame(width: 110, alignment: .leading)
        }
        .font(bold ? .caption.weight(.bold) : .caption)
        .lineLimit(1)
        .padding(.vertical, 4)
    }
}
#endif
