# Construction Management UI User Guide

User guide for the Construction Management System web application.

## Getting Started

### Accessing the Application

1. Open your browser and navigate to:
   - **Development:** `http://localhost:3000`
   - **Production:** Your deployed URL

2. You will see the login page if not authenticated.

### System Requirements

- Modern web browser (Chrome, Firefox, Safari, Edge)
- JavaScript enabled
- Minimum screen resolution: 1024x768

---

## Login

### Signing In

1. Enter your **email address** in the email field
2. Enter your **password**
3. Click **Sign in**

After successful login, you'll be redirected to the Dashboard.

### Troubleshooting Login

| Issue | Solution |
|-------|----------|
| Forgot password | Contact your administrator |
| Account locked | Wait or contact administrator |
| Invalid credentials | Check email/password spelling |

---

## Application Layout

The application has three main areas:

```
┌─────────────────────────────────────────────────┐
│                    Topbar                       │
├──────────┬──────────────────────────────────────┤
│          │                                      │
│ Sidebar  │          Main Content                │
│          │                                      │
│          │                                      │
└──────────┴──────────────────────────────────────┘
```

### Sidebar (Left)

Navigation menu with links to:
- 📊 **Dashboard** - Overview and metrics
- 📁 **Projects** - Project management
- ⚙️ **Settings** - Application settings

Click any item to navigate to that section.

### Topbar (Top)

Contains:
- **Project Selector** - Switch between projects (dropdown on the left)
- **Page Title** - Current page name
- **Notifications** - Bell icon (🔔) for alerts
- **User Menu** - Your email and Sign out button

### Main Content (Center)

Displays the current page content based on your navigation selection.

---

## Dashboard

The Dashboard provides an overview of your construction management activities.

### Dashboard Widgets

| Widget | Description |
|--------|-------------|
| Active Projects | Count of ongoing projects |
| Pending Tasks | Tasks awaiting completion |
| Team Members | Total team member count |

### Using the Dashboard

1. Click **Dashboard** in the sidebar
2. View summary metrics in the widget cards
3. Click widgets to see detailed information (when implemented)

---

## Projects

Manage all your construction projects from this page.

### Viewing Projects

1. Click **Projects** in the sidebar
2. View the project list/grid

### Project Actions

| Action | How To |
|--------|--------|
| View project | Click project name/row |
| Create project | Click "New Project" button |
| Edit project | Click edit icon on project row |
| Delete project | Click delete icon on project row |

### Project Permissions

Access depends on your role:
- `project:read` - View projects
- `project:create` - Create new projects
- `project:update` - Edit existing projects
- `project:delete` - Remove projects

---

## Settings

Configure your account and application preferences.

### Available Settings Sections

#### Profile Settings
- Update your personal information
- Change display name
- Update contact details

#### Notification Preferences
- Email notification settings
- In-app alert preferences
- Project update notifications

#### Organization Settings
- Organization-level configurations
- Team management (admin only)
- Workspace settings

---

## Topbar Features

### Project Selector

Located in the top-left of the topbar:
1. Click the project selector dropdown
2. Choose a project from the list
3. The application context switches to that project

### User Account

Located in the top-right:
- **Avatar** - Shows first letter of your email
- **Email** - Your account email address
- **Sign out** - Click to log out

### Signing Out

1. Click **Sign out** button in the topbar
2. You will be redirected to the login page
3. Your session is securely terminated

---

## Navigation

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Tab | Move between elements |
| Enter | Activate buttons/links |
| Escape | Close modals/dropdowns |

### Breadcrumbs

When available, breadcrumbs show your current location:
```
Dashboard > Projects > Project Name
```

Click any breadcrumb to navigate back.

---

## Common Tasks

### Switching Projects

1. Click the project selector in the topbar
2. Select the desired project
3. Dashboard and data update to reflect the selected project

### Checking Notifications

1. Click the bell icon (🔔) in the topbar
2. View pending notifications
3. Click a notification to see details

### Logging Out

1. Click **Sign out** in the topbar (top-right)
2. Confirm if prompted
3. You're redirected to login

---

## Troubleshooting

### Page Not Loading

1. Check your internet connection
2. Refresh the page (F5 or Ctrl+R)
3. Clear browser cache if issues persist
4. Contact support if problem continues

### Session Expired

If you see "Unauthorized" or get redirected to login:
1. Your session has expired
2. Log in again with your credentials
3. You'll be redirected to your previous page

### Access Denied

If you see "Forbidden" or "Access Denied":
1. You don't have permission for this action
2. Contact your administrator for access
3. Check if you're logged into the correct account

---

## Support

For technical support:
- Contact your system administrator
- Report issues through your organization's help desk

---

## Quick Reference

| To Do This | Go Here |
|------------|---------|
| View overview | Dashboard |
| Manage projects | Projects |
| Update profile | Settings > Profile |
| Change notifications | Settings > Notifications |
| Log out | Topbar > Sign out |
