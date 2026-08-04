// GOTCHAS.md 第 4 條:上傳進度只能透過 directUploadWillStoreFileWithXHR 這個
// delegate callback 拿到,沒有其他方式。
//
// 每個檔案各自建立一個 uploader 物件當 delegate,五個檔案同時上傳時
// 五條進度列才不會互相蓋掉(共用 this.currentRow 會壞掉)。
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
    // 在輸入框裡貼文字不要被攔截,只處理帶檔案的 paste
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

    // 伺服器端也會擋(Item 的驗證),這裡先擋是為了不要白傳一趟
    if (this.maxBytesValue > 0 && file.size > this.maxBytesValue) {
      row.textContent = `${file.name} — 超過上限,未上傳`
      return
    }
    if (file.size === 0) {
      row.textContent = `${file.name} — 是空的(0 bytes),未上傳`
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
        row.textContent = `${file.name} — 上傳失敗`
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
      return { ok: false, error: data.error ?? `建立項目失敗(${response.status})` }
    } catch {
      return { ok: false, error: "連線失敗" }
    }
  }
}
