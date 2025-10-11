from reportlab.lib.pagesizes import A4
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, FrameBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

# Output file
pdf_path = "Shubham_Kumar_European_DevOps_CV.pdf"

# Theme colors
NAVY = colors.HexColor("#003366")
LIGHT_NAVY = colors.HexColor("#e8ecf3")

# Styles
styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="HeaderTitle", fontSize=18, leading=21, textColor=NAVY, spaceAfter=4))
styles.add(ParagraphStyle(name="SubHeader", fontSize=11, leading=14, textColor=NAVY))
styles.add(ParagraphStyle(name="SectionTitle", fontSize=12, leading=14, textColor=NAVY, spaceBefore=6, spaceAfter=4, fontName="Helvetica-Bold"))
styles.add(ParagraphStyle(name="Body", fontSize=10.3, leading=13.5, textColor=colors.HexColor("#222222")))
styles.add(ParagraphStyle(name="SidebarTitle", fontSize=10.5, leading=12, textColor=NAVY, spaceBefore=6, spaceAfter=2))
styles.add(ParagraphStyle(name="SidebarText", fontSize=9.7, leading=12, textColor=NAVY))

# Layout
PAGE_W, PAGE_H = A4
LM, RM, TM, BM = 36, 36, 32, 32
SIDEBAR_W = 2.2 * inch
GUTTER = 14

def draw_bg(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(LIGHT_NAVY)
    canvas.rect(LM, BM, SIDEBAR_W, PAGE_H - TM - BM, fill=1, stroke=0)
    canvas.restoreState()

sidebar_frame = Frame(LM, BM, SIDEBAR_W, PAGE_H - TM - BM,
                      leftPadding=10, rightPadding=10, topPadding=10, bottomPadding=10, id='sidebar')
main_x = LM + SIDEBAR_W + GUTTER
main_w = PAGE_W - main_x - RM
main_frame = Frame(main_x, BM, main_w, PAGE_H - TM - BM,
                   leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0, id='main')

doc = BaseDocTemplate(pdf_path, pagesize=A4,
                      leftMargin=LM, rightMargin=RM, topMargin=TM, bottomMargin=BM)
doc.addPageTemplates([PageTemplate(id='TwoCol', frames=[sidebar_frame, main_frame], onPage=draw_bg)])

story = []

# ==== SIDEBAR ====
story.append(Paragraph("<b>CONTACT</b>", styles["SidebarTitle"]))
story.append(Paragraph("📧 <link href='mailto:shubham46.56@gmail.com'>shubham46.56@gmail.com</link>", styles["SidebarText"]))
story.append(Paragraph("🔗 <link href='https://linkedin.com/in/contactshubham-kr'>linkedin.com/in/contactshubham-kr</link>", styles["SidebarText"]))
story.append(Paragraph("🌐 <link href='https://cv-topaz-psi.vercel.app'>cv-topaz-psi.vercel.app</link>", styles["SidebarText"]))
story.append(Paragraph("💻 <link href='https://github.com/Shubham-Master'>github.com/Shubham-Master</link>", styles["SidebarText"]))
story.append(Spacer(1, 6))

story.append(Paragraph("<b>KEY SKILLS</b>", styles["SidebarTitle"]))
story.append(Paragraph("Terraform · Ansible · Docker · Jenkins · GitHub Actions · Kubernetes · Python · Go · Bash", styles["SidebarText"]))

story.append(Paragraph("<b>CLOUD</b>", styles["SidebarTitle"]))
story.append(Paragraph("AWS · Azure · GCP", styles["SidebarText"]))

story.append(Paragraph("<b>TOOLS</b>", styles["SidebarTitle"]))
story.append(Paragraph("Prometheus · Grafana · ELK · CloudWatch · GitLab", styles["SidebarText"]))

story.append(Paragraph("<b>LANGUAGES</b>", styles["SidebarTitle"]))
story.append(Paragraph("English · Hindi · Basic Dutch", styles["SidebarText"]))

# === MAIN BODY ===
story.append(FrameBreak())

story.append(Paragraph("SHUBHAM KUMAR", styles["HeaderTitle"]))
story.append(Paragraph("Senior DevOps Engineer | Multi-Cloud | CI/CD Automation", styles["SubHeader"]))
story.append(Paragraph("📍 Gurugram, India | ✈ Open to Relocation – Netherlands | Germany | UAE", styles["SubHeader"]))
story.append(Spacer(1, 5))

# === PROFILE ===
story.append(Paragraph("PROFILE SUMMARY", styles["SectionTitle"]))
story.append(Paragraph(
    "DevOps Engineer with 5+ years of experience automating infrastructure, building CI/CD pipelines, and managing multi-cloud environments (AWS, Azure, GCP). "
    "Proven ability to design scalable and secure systems while collaborating with cross-border teams in India and the Netherlands. "
    "Strong scripting background (Python, Go, Bash) focused on infrastructure as code and observability.",
    styles["Body"]))
story.append(Spacer(1, 6))

# === EXPERIENCE ===
story.append(Paragraph("PROFESSIONAL EXPERIENCE", styles["SectionTitle"]))

story.append(Paragraph("<b>AirFi Aviation Solutions</b> – Senior DevOps Engineer (Promoted from DevOps Engineer) | Bengaluru, India | 2020 – Present", styles["Body"]))
story.append(Paragraph(
    "• Led CI/CD modernization reducing release cycles by 50%.<br/>"
    "• Automated firmware deployment for 8,000+ embedded devices.<br/>"
    "• Built telemetry-based monitoring enabling predictive maintenance.<br/>"
    "• Collaborated with Netherlands HQ for global releases.<br/>"
    "• Designed Terraform provisioning and network automation across multi-cloud (AWS, Azure, GCP).<br/>"
    "• Mentored engineers and standardized DevOps practices.<br/>"
    "• Developed secure remote diagnostics reducing MTTR by 35%.", styles["Body"]))
story.append(Spacer(1, 4))

story.append(Paragraph("<b>Amazon</b> – Quality Analyst / DevOps Contributor | Bengaluru, India | 2021 – 2023", styles["Body"]))
story.append(Paragraph(
    "• Built Jenkins pipelines integrating Grafana dashboards for QA automation.<br/>"
    "• Managed AWS environments ensuring scalability and uptime.<br/>"
    "• Improved release workflows through Kubernetes-based automation.", styles["Body"]))
story.append(Spacer(1, 4))

story.append(Paragraph("<b>Extreme Soft Management & Solutions</b> – Site Reliability Engineer | Bangalore, India | 2019 – 2021", styles["Body"]))
story.append(Paragraph(
    "• Automated workflows saving 80+ engineering hours monthly.<br/>"
    "• Improved uptime via Linux hardening and deployment standardization.", styles["Body"]))
story.append(Spacer(1, 6))

# === PROJECTS ===
story.append(Paragraph("PROJECTS", styles["SectionTitle"]))
story.append(Paragraph(
    "<b>Smart Home Automation:</b> Raspberry Pi + Python + MQTT IoT setup for real-time control.<br/>"
    "<b>Personal Cloud Dashboard:</b> Serverless Next.js app (AWS Lambda + DynamoDB).<br/>"
    "<b>Flight Analytics Visualizer:</b> Python + Plotly dashboard analyzing flight and battery trends.",
    styles["Body"]))
story.append(Spacer(1, 6))

# === EDUCATION ===
story.append(Paragraph("EDUCATION", styles["SectionTitle"]))
story.append(Paragraph(
    "B.Tech – Electronics & Communication Engineering, RNS Institute of Technology, Bengaluru, India (2014 – 2018)",
    styles["Body"]))

# Build
doc.build(story)
print(f"✅ CV created successfully: {pdf_path}")
