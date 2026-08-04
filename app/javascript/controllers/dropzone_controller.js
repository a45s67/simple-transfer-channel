// Upload progress is only available through the directUploadWillStoreFileWithXHR
// delegate callback. There is no other way to get it.
//
// Each file builds its own delegate object so that five concurrent uploads keep
// five independent progress rows (a shared this.currentRow breaks).
import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["zone", "picker", "progress", "textbody"]
  static values = { url: String, directUploadUrl: String, maxBytes: Number }

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
    // Don't swallow plain-text pastes into the textarea; only handle files.
    const files = Array.from(event.clipboardData?.files ?? [])
    if (files.length === 0) return
    event.preventDefault()
    files.forEach((f) => this.upload(f))
  }

  submitText(event) {
    if (event.type === "keydown" && !((event.ctrlKey || event.metaKey) && event.key === "Enter")) return
    event.preventDefault()

    const body = this.textbodyTarget.value
    if (!body.trim()) return

    this.post({ body }).then((result) => {
      if (result.ok) this.textbodyTarget.value = ""
      else window.alert(result.error)
    })
  }

  upload(file) {
    const row = this.addRow(file.name)

    // The server validates this too (see Item); checking here just avoids
    // uploading a file that is going to be rejected anyway.
    if (this.maxBytesValue > 0 && file.size > this.maxBytesValue) {
      row.textContent = `${file.name} — over the size limit, not uploaded`
      return
    }
    if (file.size === 0) {
      row.textContent = `${file.name} — empty (0 bytes), not uploaded`
      return
    }

    const delegate = {
      directUploadWillStoreFileWithXHR(xhr) {
        xhr.upload.addEventListener("progress", (event) => {
          if (!event.lengthComputable) return
          const pct = Math.round((event.loaded / event.total) * 100)
          row.textContent = `${file.name} — ${pct}%`
        })
      }
    }

    const upload = new DirectUpload(file, this.directUploadUrlValue, delegate)

    upload.create((error, blob) => {
      if (error) {
        row.textContent = `${file.name} — upload failed`
        return
      }

      this.post({ signed_id: blob.signed_id }).then((result) => {
        if (result.ok) row.remove()
        else row.textContent = `${file.name} — ${result.error}`
      })
    })
  }

  addRow(name) {
    const row = document.createElement("div")
    row.className = "prog"
    row.textContent = `${name} — 0%`
    this.progressTarget.appendChild(row)
    return row
  }

  async post(payload) {
    const body = new FormData()
    Object.entries(payload).forEach(([k, v]) => body.append(k, v))

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "" },
        body
      })

      if (response.ok) return { ok: true }

      const data = await response.json().catch(() => ({}))
      return { ok: false, error: data.error ?? `could not create item (${response.status})` }
    } catch {
      return { ok: false, error: "connection failed" }
    }
  }
}
