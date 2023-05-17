const common = {
    parallel: 2,
    // format: ['progress-bar', 'cucumber-console-formatter', 'json:./reports/json/cucumber_report.json', 'html:./reports/html/cucumber_report.html'],
    format: ['progress-bar', 'cucumber-console-formatter'],
    paths: ['./btest/features/*.feature'],
    require: ['./btest/steps/*steps.js'],
    publishQuiet: true,
    environment: {
        API_URL: 'http://localhost:8080'
    }
}

module.exports = {
    default: {
        ...common
    },
    smoke: {
        ...common,
        tags: "@smoke",
    },
    regression: {
        ...common,
        tags: "@regression and not @smoke",
    }
};
