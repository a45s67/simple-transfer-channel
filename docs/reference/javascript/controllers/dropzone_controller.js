// 參考實作 — 未執行過,以 SPEC.md 為準
//
// GOTCHAS.md 第 4 條:進度只能透過 directUploadWillStoreFileWithXHR 拿到。
import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["zone", "picker", "progress", "textbody"]
  static values = { url: String, directUploadUrl: String }

  connect() {
    this.pasteHandler = this.onPaste.bind(this)
    document.addEventListener("paste", this.pasteHandler)
  }

  disconnect() {
    document.removeEventListener("paste", this.pasteHandler)
  }

  dragover(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("over")
  }

  dragleave() {
    this.zoneTarget.classList.remove("over")
  }

  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("over")
    Array.from(event.dataTransfer.files).forEach((f) => this.upload(f))
  }

  pick() {
    this.pickerTarget.click()
  }

  picked() {
    Array.from(this.pickerTarget.files).forEach((f) => this.upload(f))
    this.pickerTarget.value = ""
  }

  onPaste(event) {
    const files = Array.from(event.clipboardData?.files ?? [])
    if (files.length === 0) return
    event.preventDefault()
    files.forEach((f) => this.upload(f))
  }

  submitText(event) {
    if (event.type === "keydown" && !((event.ctrlKey || event.metaKey) && event.key === "Enter")) return

    const body = this.textbodyTarget.value
    if (!body.trim()) return

    this.post({ body }).then((ok) => { if (ok) this.textbodyTarget.value = "" })
  }

  upload(file) {
    const row = document.createElement("div")
    row.className = "prog"
    row.textContent = `${file.name} — 0%`
    this.progressTarget.appendChild(row)
    this.currentRow = row

    const upload = new DirectUpload(file, this.directUploadUrlValue, this)

    upload.create((error, blob) => {
      if (error) {
        row.textContent = `${file.name} — 上傳失敗`
        return
      }

      this.post({ signed_id: blob.signed_id }).then((ok) => {
        row.textContent = ok ? "" : `${file.name} — 建立項目失敗`
        if (ok) row.remove()
      })
    })
  }

  directUploadWillStoreFileWithXHR(xhr) {
    const row = this.currentRow
    xhr.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return
      const pct = Math.round((event.loaded / event.total) * 100)
      row.textContent = `${row.textContent.split(" — ")[0]} — ${pct}%`
    })
  }

  async post(payload) {
    const body = new FormData()
    Object.entries(payload).forEach(([k, v]) => body.append(k, v))

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "" },
      body
    })

    return response.ok
  }
}
