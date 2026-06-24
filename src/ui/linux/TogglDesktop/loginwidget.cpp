// Copyright 2014 Toggl Desktop developers.

#include "loginwidget.h"
#include "ui_loginwidget.h"

#include "toggl.h"

#include <QKeyEvent>
#include <QDesktopServices>

LoginWidget::LoginWidget(QStackedWidget *parent) : QWidget(parent),
ui(new Ui::LoginWidget) {
    ui->setupUi(this);

    // Redmine fork: the two credential fields are repurposed as the Redmine
    // base URL and the personal API key. Toggl-only signup/SSO paths are gone.
    ui->email->setPlaceholderText("Redmine URL (e.g. https://redmine.example.com)");
    ui->password->setPlaceholderText("API key");
    ui->password->setEchoMode(QLineEdit::Normal);

    // Indeterminate "logging in" bar, hidden until a login is in flight.
    ui->loginProgress->setRange(0, 0);
    ui->loginProgress->hide();

    connect(TogglApi::instance, SIGNAL(displayLogin(bool,uint64_t)),  // NOLINT
            this, SLOT(displayLogin(bool,uint64_t)));  // NOLINT

    connect(TogglApi::instance, SIGNAL(displayError(QString,bool)),  // NOLINT
            this, SLOT(displayError(QString,bool)));  // NOLINT
}

LoginWidget::~LoginWidget() {
    delete ui;
}

void LoginWidget::displayError(
    const QString errmsg,
    const bool user_error) {
    Q_UNUSED(errmsg);
    Q_UNUSED(user_error);
    ui->loginProgress->hide();
    enableAllControls(true);
}

void LoginWidget::enableAllControls(const bool enable) {
    ui->email->setEnabled(enable);
    ui->password->setEnabled(enable);
    ui->login->setEnabled(enable);
}

void LoginWidget::display() {
    ui->loginProgress->hide();
    qobject_cast<QStackedWidget*>(parent())->setCurrentWidget(this);
}

void LoginWidget::keyPressEvent(QKeyEvent* event) {
    if (event->key() == Qt::Key_Enter || event->key() == Qt::Key_Return) {
        on_login_clicked();
    }
}

void LoginWidget::mousePressEvent(QMouseEvent* event) {
    Q_UNUSED(event);
    setFocus();
}

void LoginWidget::displayLogin(
    const bool open,
    const uint64_t user_id) {

    if (open) {
        display();
        ui->email->setFocus();
    }
    if (user_id) {
        ui->password->clear();
    }

    ui->loginProgress->hide();
    enableAllControls(true);
}

void LoginWidget::on_login_clicked() {
    if (!validateFields()) {
        return;
    }
    enableAllControls(false);
    ui->loginProgress->show();
    // email field holds the Redmine URL; password field holds the API key.
    TogglApi::instance->setBaseURL(ui->email->text());
    TogglApi::instance->login(ui->password->text(), ui->password->text());
}

bool LoginWidget::validateFields() {
    if (ui->email->text().isEmpty()) {
        ui->email->setFocus();
        TogglApi::instance->displayError(QString("Please enter your Redmine URL"), true);
        return false;
    }
    if (ui->password->text().isEmpty()) {
        ui->password->setFocus();
        TogglApi::instance->displayError(QString("An API key is required"), true);
        return false;
    }
    return true;
}
