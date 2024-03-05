#!/bin/bash

WORKDIR=$(pwd)

cd ${WORKDIR}/functions/addTask
npm install
npm run build
mkdir dist
cp -r ./*.js dist/
cp -r ./node_modules dist/
cd dist
zip -r ${WORKDIR}/add_task_lambda_function.zip .

cd ${WORKDIR}/functions/postConfirmation
npm install
npm run build
mkdir dist
cp -r ./*.js dist/
cp -r ./node_modules dist/
cd dist
zip -r ${WORKDIR}/post_confirmation_lambda_function.zip .

