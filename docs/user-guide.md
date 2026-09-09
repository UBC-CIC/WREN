# WREN User Guide

This guide covers how to get started with **WREN** — from creating your account to using it as a **Student**, **Department Admin**, or **System Admin**. Start with [Part 1: Getting Started](#part-1-getting-started-all-users), then jump to the part that matches your role.

Throughout the user guide, there are different names to refer to the product. The name **WREN** represents the product's broader application, while the Literary Expression Organization & Navigation **(LEON)** name indicates the product's origins in providing writing feedback in a legal context. **Both names refer to the same product, but within different contexts**. 

Similarly, you will see **System Admin** used throughout this user guide, but in the API and database, this role is called the **Technical Admin**.

## Table of Contents

- [Part 1: Getting Started (All Users)](#part-1-getting-started-all-users)
  - [1.1 Log In](#11-log-in)
  - [1.2 Create an Account (First-Time Users Only)](#12-create-an-account-first-time-users-only)
  - [1.3 Choosing Your Account View](#13-choosing-your-account-view)
- [Part 2: Student Guide](#part-2-student-guide)
  - [2.1 Creating a New Document Draft](#21-creating-a-new-document-draft)
  - [2.2 Opening and Reviewing Your Document](#22-opening-and-reviewing-your-document)
  - [2.3 Using AI Debrief](#23-using-ai-debrief)
  - [2.4 Using Ask WREN](#24-using-ask-WREN)
  - [Quick Recap — Student](#quick-recap--student)
- [Part 3: Department Admin Guide](#part-3-department-admin-guide)
  - [3.1 How the Department Admin Screens Are Organized](#31-how-the-department-admin-screens-are-organized)
  - [3.2 Opening a Document Type](#32-opening-a-document-type)
  - [3.3 Setting Up the Evaluation Rubric](#33-setting-up-the-evaluation-rubric)
  - [3.4 Reviewing Analytics](#34-reviewing-analytics)
  - [Quick Reference — Department Admin](#quick-reference--department-admin)
- [Part 4: System Admin Guide](#part-4-system-admin-guide)
  - [4.1 How the System Admin Screens Are Organized](#41-how-the-system-admin-screens-are-organized)
  - [4.2 Model Configuration](#42-model-configuration)
  - [4.3 Setting Usage Limits](#43-setting-usage-limits)
  - [4.4 Creating New Departments](#44-creating-new-departments)
  - [4.5 Managing Departments](#45-managing-departments)
  - [4.6 Department Prompt](#46-department-prompt)
  - [4.7 Reviewing Department Analytics](#47-reviewing-department-analytics)
  - [Quick Reference — System Admin](#quick-reference--system-admin)

---

## Part 1: Getting Started (All Users)

### 1.1 Log In

> **First time here?** Create an account first — see [1.2 Create an Account](#12-create-an-account-first-time-users-only), then return here.

1. Open the WREN URL your administrator gave you (or the AWS Amplify URL).
2. Enter the email address and password you used when creating your account.
3. Click **Login**.
4. You land on the dashboard.

### 1.2 Create an Account (First-Time Users Only)

**Note:** Skip this section if you already have an account and go to [1.1 Log In](#11-log-in).

1. Click **Sign Up**.
2. Enter:
   - Your institutional email address
   - A new password for WREN

   Follow the password rules listed on the page (length, letters, numbers, or symbols as shown).

3. After you submit, WREN sends a **verification code** to that email.

   **Important:** Keep the sign-up page open while you check email.

4. Find the code in your inbox (check spam if it does not arrive within a few minutes).
5. Return to the sign-up page and enter the code.
6. Your account is ready. Continue to [1.1 Log In](#11-log-in).

## Part 2: Student Guide

On the **Student Dashboard** you will see your existing drafts, or an empty state if you have not created one yet.

<img width="957" height="395" alt="Student dashboard" src="https://github.com/user-attachments/assets/a0050ec6-575d-48fe-bc46-d5aecbdb2107" />

### 2.1 Creating a New Document Draft

1. From the Student Dashboard, find **New Document** in the top-right corner of the screen (next to **All Documents**, which is the page you are currently on).
<img width="1914" height="790" alt="Screenshot 2026-08-24 164814" src="https://github.com/user-attachments/assets/2ad36a0a-4d9b-4baf-83a6-f7772f10c440" />

2. Click **New Document**.

3. Select your department.

4. Choose your document type — for example, **Legal Memorandum**.

5. Give your draft a name.

6. Click **Choose File** and select the DOCX file from your computer that you want to upload.

<img width="956" height="368" alt="image" src="https://github.com/user-attachments/assets/5c284420-bbfa-4e77-b675-14e2dc247690" />

8. After uploading, you will automatically be returned to the **My Documents** page, where you will now see your newly uploaded draft listed.
9. After uploading, you will be taken to the following page:
<img width="956" height="415" alt="image" src="https://github.com/user-attachments/assets/c652ca27-01f6-4aa9-9314-985318bcb573" />

### 2.2 Opening and Reviewing Your Document

1. From **All Documents**, click the draft you want to open. The editor shows a continuous document on the right and a side panel on the left.
2. The document is not split into pages on screen. Headers and footers sit at the top and bottom of the draft. The **Contents** panel shows the draft version, word count, and an estimated printed page count (US Letter). Heading 1–3 styles build an outline; click a heading to jump to it.
3. Hover or drag the scrollbar to see an estimated printed page, for example **Page 2 of 17**. That is how the document is expected to paginate on preview or export, not a live page break in the editor.
4. The left icon rail switches the panel between **Contents**, **Ask WREN**, and **AI Debrief**.
<img width="1912" height="829" alt="Editor with Ask WREN and AI Debrief" src="https://github.com/user-attachments/assets/2bc18352-af6a-48dd-a61a-5db705046320" />

**Other options in this view:**

- **Upload a new draft** — use this if changes were made to your document in another editor and you need LEON to review the updated version.
  
<img width="960" height="412" alt="image" src="https://github.com/user-attachments/assets/484861de-deb2-4fcf-b58e-216dee59eb97" />

- **Export** — use this to download your document after changes have been made.

<img width="959" height="412" alt="image" src="https://github.com/user-attachments/assets/d31b8995-9545-4531-8c9e-04411dbd8c70" />

- **Adjust the panel** — click on the grey bar on the right side of the AI debrief to expand or minimize the panel.

<img width="959" height="412" alt="image" src="https://github.com/user-attachments/assets/544ace4d-b433-437f-8472-14376b80b177" />

### 2.3 Using AI Debrief

1. Click **Regenerate** to generate a new AI Debrief report on your document.
<img width="956" height="413" alt="image" src="https://github.com/user-attachments/assets/3f598ac5-b9fc-4077-b0b8-a6b41b98f6a8" />
2. To view a previously generated report, click the **drop-down arrow** and select an earlier draft's report from the list.
<img width="959" height="416" alt="image" src="https://github.com/user-attachments/assets/3ce5e503-c9b9-498c-bbae-457a354d57d9" />

1. Click **Ask WREN** (the WREN icon) on the left rail.
2. Ask questions about the debrief, your draft, or writing craft (clarity, organization, tone, and similar).
3. Click a quoted phrase in a reply to jump to that passage.
<img width="958" height="412" alt="Ask WREN chat" src="https://github.com/user-attachments/assets/0b5d2ba7-27b3-4c33-a726-e6882021007e" />

Ask WREN will not write or rewrite your sentences, fact-check legal or technical claims, or answer questions unrelated to this draft.

### Quick Recap — Student

| Task | Where to go |
| --- | --- |
| Create an account | Sign Up → email/password → verify the email code |
| Log in | Login → email/password |
| Start a new draft | Student Dashboard → New Document → department → document type → upload .docx or .pdf → Activate Editor |
| Review AI feedback | Open document → AI Debrief |
| Ask questions about your draft | Open document → Ask WREN |
| Update a draft | Editor → Upload New Draft |
| Save a copy | Editor → Export (DOCX or PDF) |

---

## Part 3: Department Admin Guide

As a **Department Admin**, you configure document types and evaluation criteria for the department(s) you administer, and you review aggregate analytics. Student-facing debriefs are generated against the rubric you save.

After you choose **Department Admin** as your account view (see [1.3](#13-choosing-your-account-view)), you land on the Department Admin dashboard.

### 3.1 How the Department Admin Screens Are Organized

- **Profile** — switch account view (Student / Department Admin / System Admin, depending on your roles).
<img width="944" height="410" alt="Switch account view from profile" src="https://github.com/user-attachments/assets/60265c0f-df66-4185-ac91-986725b99043" />
- **Dashboard** — document types for the department you are managing. If you administer more than one department, a selector on the banner switches which department you are editing. **Create New Document Type** is on the right.
<img width="943" height="412" alt="Department Admin dashboard" src="https://github.com/user-attachments/assets/4beb78da-7c6a-462c-ba6f-94749121db63" />
- **Document type** — opens when you select a type. Two areas: **Evaluation Rubric** and **Analytics**.
<img width="950" height="413" alt="Document type Evaluation Rubric and Analytics" src="https://github.com/user-attachments/assets/3c9ac6ea-feee-4d36-9d63-9f507a28a9e9" />
- **Evaluation Rubric** — **Document Context** (purpose, common mistakes, additional background, citation guide) and **Evaluation Criteria** (categories the AI should use). Click **Save Rubric** when you are done; this screen does not autosave.
<img width="935" height="409" alt="Evaluation Rubric categories" src="https://github.com/user-attachments/assets/361ff81e-4ba7-4dd5-ad90-c683bb13a939" />
- **Analytics** — student improvement trends, AI Debrief helpfulness (aggregate yes/no ratings), and section applicability. Figures are aggregates, not per-student scores.
<img width="950" height="407" alt="Document type analytics" src="https://github.com/user-attachments/assets/1b1427c0-02f6-4dd2-9f74-ff7e1c45ed16" />

- **Profile** — click your profile to switch your account view between Student and Department Admin.
  
<img width="1870" height="813" alt="image" src="https://github.com/user-attachments/assets/529f9101-fb8e-4dd8-9e32-9d36953b4ce4" />

- **Dashboard** — the main screen after choosing Department Admin. Your existing document types are listed here, with the **Create New Document Type** button on the right side of the screen.
  
<img width="943" height="412" alt="image" src="https://github.com/user-attachments/assets/4beb78da-7c6a-462c-ba6f-94749121db63" />

- **Document Controls** — opens when you select or create a document type. It's organized as two tabs: **Evaluation** and **Analytics**.
  
<img width="950" height="413" alt="image" src="https://github.com/user-attachments/assets/3c9ac6ea-feee-4d36-9d63-9f507a28a9e9" />

- **Inside Evaluation Settings** — **General Information** sits at the top, followed by your list of **Categories**. Clicking a category opens its configuration form.

<img width="935" height="409" alt="image" src="https://github.com/user-attachments/assets/361ff81e-4ba7-4dd5-ad90-c683bb13a939" />

- **Inside Analytics** — **Student Improvement Trends** appears first, followed by **AI Debrief Helpfulness** and **Feedback Section Applicability**

<img width="950" height="407" alt="image" src="https://github.com/user-attachments/assets/1b1427c0-02f6-4dd2-9f74-ff7e1c45ed16" />

### 3.2 Opening a Document Type

**Entering document type information**

1. Go to the **document context** section.
2. Enter a description of the document's purpose and expected content.
3. Add any other reference information relevant to the document type.

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/7ee641f9-4749-404e-b308-146254404519" />

**Select or create evaluation criteria**

1. Select an existing category to open its configuration form, or
2. Click **add custom criterion** to add a new one.

<img width="859" height="401" alt="image" src="https://github.com/user-attachments/assets/47d93e8b-8b9d-404f-acac-57c5fd833046" />

1. Expand **Document Context**.
2. Fill in **Purpose**, **Common mistakes to avoid**, and **Additional background**.
3. Optionally choose a **Citation guide** (for example McGill Guide) so the AI evaluates references consistently.

1. Click into a category (e.g., "Clarity").
2. Fill in the form with the requirements the AI should evaluate against for this document type — for example, what does clarity look like for an appellate factum?
3. Your changes save automatically as you go, so you can leave and return without losing progress.

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/c62f4476-d14e-4155-a50f-2ea6e1d7d27d" />

### 3.3 Reviewing Analytics

- **Student improvement** — how debrief-related signals change over time (date-range presets or custom range).
- **AI Debrief helpfulness** — aggregate student ratings (helpful / not helpful) and optional comments.
- **Section applicability** — whether feedback sections applied to the draft, in aggregate.

View whether students addressed the feedback flagged their previous drafts.

<img width="706" height="399" alt="image" src="https://github.com/user-attachments/assets/d7558de7-dc06-495a-bd37-558cf0a87078" />
<img width="544" height="122" alt="image" src="https://github.com/user-attachments/assets/8712c5ea-ffa1-4817-853f-fae22da2fe25" />

**Check AI Debrief quality**

1. Review the Helpfulness Breakdown - which provides a visual to see what percentage of feedback was both helpful and not helpful
2. Review Feedback Section Applicability — applicable/not applicable indicators tied to each evaluation category you configured in [3.3 Setting Up Evaluation Settings](#33-setting-up-evaluation-settings) (e.g., "Was the tone feedback useful? Yes/No").

<img width="1447" height="685" alt="image" src="https://github.com/user-attachments/assets/d70c2cf6-a983-4eb5-8d1f-c5f29e50a9a4" />

### Quick Reference — Department Admin

| Action | What happens |
| --- | --- |
| Switch department | Use the department selector on the dashboard banner (if you administer more than one) |
| Create a document type | Create New Document Type → name → Create |
| Open a type | Click it in the list |
| Set coaching rules | Evaluation Rubric → Document Context + criteria → Save Rubric |
| Check results | Analytics for that document type |

---

## Part 4: System Admin Guide

As a **System Admin**, you sit above the department level: you choose the Bedrock model, set platform usage limits, create departments, manage users and access, edit department-level prompts, and review department analytics.

After you choose **System Admin** as your account view (see [1.3](#13-choosing-your-account-view)), you land on **System Configuration** and the department list.

### 4.1 How the System Admin Screens Are Organized

Before diving into the steps, here's where things live on the platform:

- **Profile** — click your profile to switch your account view between Student, Department Admin, and System Admin.

<img width="1870" height="813" alt="image" src="https://github.com/user-attachments/assets/529f9101-fb8e-4dd8-9e32-9d36953b4ce4" />

- **Dashboard** — the main screen after choosing System Admin. Your list of departments is shown here, alongside **Usage Limits** and **Model Configuration**.

<img width="944" height="297" alt="image" src="https://github.com/user-attachments/assets/04c3dd29-6923-433b-9e4d-211c27c67975" />
<img width="917" height="310" alt="image" src="https://github.com/user-attachments/assets/fa25a40d-91a0-4b9f-a1b6-16faaab5cf35" />

- **Department Controls** — opens when you select or create a department. It's organized into three areas: **Users**, **Manage Department Prompt**, and **View Analytics**.
- **Inside Users** — the list of active users in the department, where you can promote roles or lock the department from student access.

<img width="1867" height="810" alt="image" src="https://github.com/user-attachments/assets/f37e9e4d-f13a-4149-8f11-03550340dc3a" />


- **Inside Manage Department Prompt** — **Department Context** sits at the top, followed by **Writing Standards**, then **Restricted Topics**.


- **Inside Analytics** — **Active Users** appears first, followed by **Documents Generated**, then **Debriefs Generated**.

### 4.2 Model Configuration

1. Go to **System Admin Dashboard → System Configuration → Model Configuration**.
2. Review the list of available AI models.
3. Select the model you want to set as the platform default.
4. Click **Save**.

<img width="910" height="385" alt="image" src="https://github.com/user-attachments/assets/b9ec4bef-0b50-4b22-9c22-aaab06e8ee62" />

**Notes:**

Model changes apply immediately to new AI Debrief and Ask WREN calls. Existing debriefs are unchanged. Different models can differ in quality, cost, and latency.

### 4.3 Setting Usage Limits

1. Go to **System Admin Dashboard → System Configuration → Usage Limits**.
2. Set limits for:
   - **AI Debriefs allowed** — the maximum number of debriefs a user or department can generate in a given period.
   - **Documents allowed** — the maximum number of documents a user or department can create or process in a given period.
3. Choose whether limits apply platform-wide or per department.
4. Click **Save Changes**.

<img width="931" height="413" alt="image" src="https://github.com/user-attachments/assets/4e046f13-c2c6-4150-8bcc-68c60f85a331" />

**Notes:**

These limits apply to all users in all departments. They are not per-calendar-period quotas.

### 4.4 Creating New Departments

1. Go to **System Admin Dashboard → Departments → Create New Department**.

<img width="936" height="381" alt="image" src="https://github.com/user-attachments/assets/14cff36a-00bc-4265-8c91-4074eb697c56" />

3. Enter the department name.

<img width="892" height="375" alt="image" src="https://github.com/user-attachments/assets/cd9e8bfd-554e-484d-9754-affc81143f29" />

5. Assign an initial Department Admin by clicking on the pen symbol on the right of a user's name and selecting department admin  (optional — can be done later from Users, see [4.5 Managing Departments](#45-managing-departments)).

<img width="628" height="742" alt="image" src="https://github.com/user-attachments/assets/8b8715d7-ea2e-4f61-9a1e-f08e26443295" />

**Notes:**

- Once created, a department appears in the department list and can be opened as described in [4.5 Managing Departments](#45-managing-departments).
- Departments generally can't be merged after creation, so plan your structure before creating many of them.
- Set initial usage limits, or leave them at the platform default (see [4.3 Setting Usage Limits](#43-setting-usage-limits)).

### 4.5 Managing Departments

1. Go to **System Admin Dashboard → Departments** and select the department you want to manage.
<img width="936" height="381" alt="image" src="https://github.com/user-attachments/assets/14cff36a-00bc-4265-8c91-4074eb697c56" />

2. Click **Users** to:
   - View the list of currently active users in the department.
   - Select a user to promote or change their role — for example, promoting a Student to **Department Admin**.
   - Deactivate or remove a user if needed.
3. Click **Lock Department Access** to prevent students from logging in or using platform features while keeping admin/staff access intact. Use this for maintenance, review periods, or restructuring.

<img width="1864" height="805" alt="names_emails_only_blurred" src="https://github.com/user-attachments/assets/09497a94-13f9-4f70-ae40-61b8c14de4ef" />

**Notes:**

- Role promotions typically take effect immediately.
- Locking a department does not delete data — it only restricts student-level access until unlocked.

### 4.6 Department-Level Prompt Management

1. Go to **System Admin Dashboard → Departments → [Department Name] → Manage Department Prompt**.

2. Configure the following:
   - **Department Context** — background information the AI should always consider for this department (e.g., subject area, program level, institutional norms).
   - **Writing Standards** — style, tone, formatting, and citation requirements the AI should follow when generating documents or debriefs for this department.
   - **Restricted Topics** — a list of topics, terms, or content areas the AI should avoid or flag when interacting with this department's users.
3. Save prompt.
4. Optionally, test the configuration by generating a sample document or debrief before rolling it out.

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/c739a17c-7454-493e-b3f5-2e526a76cff6" />

**Notes:**

1. Open the department → **Manage Department Prompt**.
2. Fill in:
   - **Department Context** — who the writers are and what the program is
   - **Writing Standards** — citation style, register, formatting
   - **Restricted Topics** — subjects the coach should avoid or flag
3. Click **Save Prompt**.

These instructions apply across document types in that department. Per-type detail still lives in the Department Admin Evaluation Rubric.

1. Go to **System Admin Dashboard → Departments → [Department Name] → View Analytics** (or a platform-wide analytics view, if available).
2. Review key metrics, including:
   - **Active Users** — number of users who have logged in or used the platform within a selected time range.
   - **Total Documents** — total document creation volume over time.
   - **Total Drafts** — total AI debrief volume over time.

<img width="911" height="302" alt="image" src="https://github.com/user-attachments/assets/539979ef-8a54-41a8-bfc3-764fc87d4b43" />
<img width="725" height="296" alt="image" src="https://github.com/user-attachments/assets/3b319c83-71de-4e06-8862-42ef7101baa6" />

1. Open the department → **View Analytics**.
2. Review totals for documents, drafts, and active users, plus breakdown by document type and usage over time.

Figures are aggregates. They do not include per-student scores.

### Quick Reference — System Admin

| Action | Where to go |
| --- | --- |
| Choose AI model | Dashboard → Model Configuration |
| Set usage limits | Dashboard → Usage Limits |
| Create a department | Dashboard → create department |
| Promote or manage users | Department → Manage Users |
| Lock or open student access | Department → Lock / Open |
| Set department context and standards | Department → Manage Department Prompt |
| Review department analytics | Department → View Analytics |
