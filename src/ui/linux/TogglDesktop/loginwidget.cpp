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
    // base URL and the personal API key; Toggl-only auth paths are hidden.
    ui->email->setPlaceholderText("Redmine URL (e.g. https://redmine.example.com)");
    ui->password->setPlaceholderText("API key");
    ui->password->setEchoMode(QLineEdit::Normal);
    ui->forgotPassword->hide();
    ui->signup->hide();
    ui->viewchangelabel->hide();

    connect(TogglApi::instance, SIGNAL(displayLogin(bool,uint64_t)),  // NOLINT
            this, SLOT(displayLogin(bool,uint64_t)));  // NOLINT

    connect(TogglApi::instance, SIGNAL(setCountries(QVector<CountryView * >)),  // NOLINT
            this, SLOT(setCountries(QVector<CountryView * >)));  // NOLINT

    connect(TogglApi::instance, SIGNAL(displayError(QString,bool)),  // NOLINT
            this, SLOT(displayError(QString,bool)));  // NOLINT

    signupVisible = true;
    countriesLoaded = false;
    selectedCountryId = UINT64_MAX;

    on_viewchangelabel_linkActivated("");
}

LoginWidget::~LoginWidget() {
    delete ui;
}

void LoginWidget::displayError(
    const QString errmsg,
    const bool user_error) {
    Q_UNUSED(errmsg);
    Q_UNUSED(user_error);
    enableAllControls(true);
}

void LoginWidget::enableAllControls(const bool enable) {
    ui->email->setEnabled(enable);
    ui->password->setEnabled(enable);
    ui->login->setEnabled(enable);
    ui->signup->setEnabled(enable);
    ui->forgotPassword->setEnabled(enable);
    ui->viewchangelabel->setEnabled(enable);
}

void LoginWidget::display() {
    signupVisible = true;
    on_viewchangelabel_linkActivated("");
    qobject_cast<QStackedWidget*>(parent())->setCurrentWidget(this);
}

void LoginWidget::keyPressEvent(QKeyEvent* event) {
    if (event->key() == Qt::Key_Enter || event->key() == Qt::Key_Return) {
        if (signupVisible) {
            on_signup_clicked();
        } else {
            on_login_clicked();
        }
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

    // Enable all
    enableAllControls(true);
}

void LoginWidget::on_login_clicked() {
    if (!validateFields(false)) {
        return;
    }
    enableAllControls(false);
    // email field holds the Redmine URL; password field holds the API key.
    TogglApi::instance->setBaseURL(ui->email->text());
    TogglApi::instance->login(ui->password->text(), ui->password->text());
}

bool LoginWidget::validateFields(bool signup, bool google) {
    if (google)
        signup = true;
    if (!google) {
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
    }
    if (signup) {
        if (selectedCountryId == UINT64_MAX) {
            ui->countryComboBox->setFocus();
            TogglApi::instance->displayError(QString("Please select Country before signing up"), true);
            return false;
        }
        if (ui->tosCheckBox->checkState() == Qt::Unchecked) {
            ui->tosCheckBox->setFocus();
            TogglApi::instance->displayError(QString("You must agree to the terms of service and privacy policy to use Toggl"), true);
            return false;
        }
    }
    return true;
}

void LoginWidget::on_signup_clicked() {
    if (!validateFields(true)) {
        return;
    }
    TogglApi::instance->signup(ui->email->text(), ui->password->text(), selectedCountryId);
}

void LoginWidget::setCountries(
    QVector<CountryView * > list) {
    ui->countryComboBox->clear();
    ui->countryComboBox->addItem("  -- Select country --   ");
    foreach(CountryView *view, list) {
        ui->countryComboBox->addItem(view->Text, QVariant::fromValue(view));
    }
}

void LoginWidget::on_viewchangelabel_linkActivated(const QString &link)
{
    Q_UNUSED(link)
    if (signupVisible) {
        ui->signupWidget->hide();
        ui->loginWidget->show();
        ui->viewchangelabel->setText("<html><head/><body><a href='#' style='cursor:pointer;font-weight:bold;text-decoration:none;color:#fff;'>Sign up for free</a></body></html>");
        signupVisible = false;
    } else {
        ui->loginWidget->hide();
        ui->signupWidget->show();
        ui->viewchangelabel->setText("<html><head/><body><a href='#' style='cursor:pointer;font-weight:bold;text-decoration:none;color:#fff;'>Back to login</a></body></html>");
        signupVisible = true;
        if (!countriesLoaded) {
            TogglApi::instance->getCountries();
            countriesLoaded = true;
        }
    }
}

void LoginWidget::on_countryComboBox_currentIndexChanged(int index)
{
    if (index == 0) {
        selectedCountryId = UINT64_MAX;
        return;
    }
    QVariant data = ui->countryComboBox->currentData();
    if (data.canConvert<CountryView *>()) {
        CountryView *view = data.value<CountryView *>();
        selectedCountryId = view->ID;
    }
}
