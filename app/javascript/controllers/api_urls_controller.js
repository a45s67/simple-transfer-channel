// The curl URLs carry their own authorization and expire five minutes after
// they are minted, so the page refreshes them before that -- whatever is on
// screen is always something that still works. A URL already copied away keeps
// its own five minutes; that short window is the whole point of putting the
// token in the URL.
//
// One token per page, not one per item: items arrive by Turbo broadcast from a
// partial that has no request to build an absolute URL from, so they render an
// empty command and this controller fills it in on targetConnected.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["uploadCommand", "downloadCommand"]
  static values = { refreshUrl: String, uploadUrl: String, downloadBase: String, ttlSeconds: Number }

  connect() {
    this.render()
    const seconds = Math.max(this.ttlSecondsValue * 0.9, 30)
    this.timer = setInterval(() => this.refresh(), seconds * 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  downloadCommandTargetConnected(element) {
    this.renderDownload(element)
  }

  async refresh() {
    try {
      const response = await fetch(this.refreshUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      const data = await response.json()
      this.uploadUrlValue = data.upload_url
      this.downloadBaseValue = data.download_base
      this.render()
    } catch {
      // Offline, or the session went away. The next tick tries again.
    }
  }

  render() {
    if (this.hasUploadCommandTarget) {
      this.uploadCommandTarget.textContent = `curl -T ./file.zip ${this.uploadUrlValue}`
    }
    this.downloadCommandTargets.forEach((element) => this.renderDownload(element))
  }

  renderDownload(element) {
    const name = encodeURIComponent(element.dataset.filename)
    element.textContent = `curl -O ${this.downloadBaseValue}/${element.dataset.itemId}/${name}`
  }
}
