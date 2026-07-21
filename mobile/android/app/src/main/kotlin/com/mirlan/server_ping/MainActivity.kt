package com.mirlan.server_ping

import android.graphics.pdf.PdfDocument
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val pdfChannel = "autolab/pdf"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pdfChannel).setMethodCallHandler { call, result ->
            if (call.method != "htmlToPdf") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val html = call.argument<String>("html")
            if (html.isNullOrBlank()) {
                result.error("EMPTY_HTML", "HTML документа пустой.", null)
                return@setMethodCallHandler
            }

            createPdfFromHtml(html, result)
        }
    }

    private fun createPdfFromHtml(html: String, result: MethodChannel.Result) {
        runOnUiThread {
            val container = FrameLayout(this)
            val webView = WebView(this)
            var finished = false

            fun cleanup() {
                try {
                    (container.parent as? ViewGroup)?.removeView(container)
                    webView.destroy()
                } catch (_: Throwable) {
                }
            }

            fun fail(code: String, message: String) {
                if (finished) return
                finished = true
                cleanup()
                result.error(code, message, null)
            }

            fun succeed(bytes: ByteArray) {
                if (finished) return
                finished = true
                cleanup()
                result.success(bytes)
            }

            webView.settings.javaScriptEnabled = true
            webView.settings.loadWithOverviewMode = true
            webView.settings.useWideViewPort = true

            container.addView(
                webView,
                FrameLayout.LayoutParams(794, 1123)
            )
            addContentView(
                container,
                ViewGroup.LayoutParams(1, 1)
            )

            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String?) {
                    view.postDelayed({
                        view.evaluateJavascript(
                            "String(document.querySelectorAll('.page').length || Math.max(1, Math.ceil(document.body.scrollHeight / 1123)))"
                        ) { rawCount ->
                            val pageCount = rawCount
                                ?.trim('"')
                                ?.toIntOrNull()
                                ?.coerceAtLeast(1)
                                ?: 1
                            writeWebViewPdfPages(view, pageCount, ::succeed, ::fail)
                        }
                    }, 700)
                }
            }

            webView.loadDataWithBaseURL(
                "file:///android_asset/flutter_assets/assets/",
                html,
                "text/html",
                "UTF-8",
                null
            )
        }
    }

    private fun writeWebViewPdfPages(
        webView: WebView,
        pageCount: Int,
        succeed: (ByteArray) -> Unit,
        fail: (String, String) -> Unit
    ) {
        try {
            val density = resources.displayMetrics.density
            val sourceWidth = (794 * density).toInt()
            val sourcePageHeight = (1123 * density).toInt()
            val pdfWidth = 595
            val pdfHeight = 842
            val document = PdfDocument()

            fun finishDocument() {
                try {
                    val output = ByteArrayOutputStream()
                    document.writeTo(output)
                    document.close()
                    succeed(output.toByteArray())
                } catch (error: Throwable) {
                    try {
                        document.close()
                    } catch (_: Throwable) {
                    }
                    fail("PDF_WRITE_FAILED", error.message ?: "Не удалось записать PDF.")
                }
            }

            fun renderPage(pageIndex: Int) {
                if (pageIndex >= pageCount) {
                    finishDocument()
                    return
                }

                val script = """
                    (function(){
                      document.documentElement.style.background = '#fff';
                      document.body.style.background = '#fff';
                      document.body.style.padding = '0';
                      document.body.style.margin = '0';
                      document.querySelectorAll('.page').forEach(function(page, index) {
                        page.style.display = index === $pageIndex ? 'block' : 'none';
                        page.style.margin = '0';
                        page.style.boxShadow = 'none';
                        page.style.width = '210mm';
                        page.style.height = '297mm';
                        page.style.minHeight = '297mm';
                      });
                      'ok';
                    })();
                """.trimIndent()

                webView.evaluateJavascript(script) {
                    webView.postDelayed({
                        webView.measure(
                            View.MeasureSpec.makeMeasureSpec(sourceWidth, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(sourcePageHeight, View.MeasureSpec.EXACTLY)
                        )
                        webView.layout(0, 0, sourceWidth, sourcePageHeight)

                        val previousScrollX = webView.scrollX
                        val previousScrollY = webView.scrollY
                        webView.scrollTo(0, 0)

                        val pageInfo = PdfDocument.PageInfo.Builder(pdfWidth, pdfHeight, pageIndex + 1).create()
                        val page = document.startPage(pageInfo)
                        page.canvas.scale(
                            pdfWidth.toFloat() / sourceWidth.toFloat(),
                            pdfHeight.toFloat() / sourcePageHeight.toFloat()
                        )
                        webView.draw(page.canvas)
                        document.finishPage(page)
                        webView.scrollTo(previousScrollX, previousScrollY)

                        renderPage(pageIndex + 1)
                    }, 120)
                }
            }

            renderPage(0)
        } catch (error: Throwable) {
            fail("PDF_RENDER_FAILED", error.message ?: "Не удалось создать PDF из документа.")
        }
    }
}
