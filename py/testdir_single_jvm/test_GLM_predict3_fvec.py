import unittest, time, sys, csv
sys.path.extend(['.','..','py'])
import h2o, h2o_cmd, h2o_hosts, h2o_import as h2i, h2o_glm, h2o_exec as h2e

DO_BUG=False
DO_BUG2=False
# translate provides the mapping between original and predicted
# since GLM is binomial, We predict 0 for 0 and 1 for > 0
def compare_csv_last_col(csvPathname, msg, translate=None, skipHeader=False):
    predictOutput = []
    with open(csvPathname, 'rb') as f:
        reader = csv.reader(f)
        print "csv read of", csvPathname
        rowNum = 0
        for row in reader:
            # print the last col
            # ignore the first row ..header
            if skipHeader and rowNum==0:
                print "Skipping header in this csv"
            else:
                output = row[-1]
                if translate:
                    output = translate[int(output)]
                # only print first 10 for seeing
                if rowNum<10: print msg, row[-1], output
                predictOutput.append(output)
            rowNum += 1
    return (rowNum, predictOutput)

class Basic(unittest.TestCase):
    def tearDown(self):
        h2o.check_sandbox_for_errors()

    @classmethod
    def setUpClass(cls):
        global localhost
        localhost = h2o.decide_if_localhost()
        if (localhost):
            h2o.build_cloud(node_count=1)
        else:
            h2o_hosts.build_cloud_with_hosts(node_count=1)

    @classmethod
    def tearDownClass(cls):
        h2o.tear_down_cloud()

    def test_GLM_predict3_fvec(self):
        h2o.beta_features = True
        SYNDATASETS_DIR = h2o.make_syn_dir()

        trees = 15
        timeoutSecs = 120
        csvPathname = 'standard/covtype.data'
        hexKey = 'covtype.data.hex'

        predictHexKey = 'predict.hex'
        predictCsv = 'predict.csv'

        execHexKey = 'A.hex'
        execCsv = 'exec.csv'

        bucket = 'home-0xdiag-datasets'

        csvPredictPathname = SYNDATASETS_DIR + "/" + predictCsv
        csvExecPathname = SYNDATASETS_DIR + "/" + execCsv
        # for using below in csv reader
        csvFullname = h2i.find_folder_and_filename(bucket, csvPathname, schema='put', returnFullPath=True)

        def predict_and_compare_csvs(model_key):
            start = time.time()
            predict = h2o_cmd.runPredict(model_key=model_key, data_key=hexKey, destination_key=predictHexKey)
            print "runPredict end on ", hexKey, " took", time.time() - start, 'seconds'
            h2o.check_sandbox_for_errors()
            inspect = h2o_cmd.runInspect(key=predictHexKey)
            h2o_cmd.infoFromInspect(inspect, 'predict.hex')

            h2o.nodes[0].csv_download(src_key=predictHexKey, csvPathname=csvPredictPathname)
            h2o.nodes[0].csv_download(src_key=execHexKey, csvPathname=csvExecPathname)
            h2o.check_sandbox_for_errors()

            print "Do a check of the original output col against predicted output"
            translate = {1: 0.0, 2: 1.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0, 7: 1.0}
            (rowNum1, originalOutput) = compare_csv_last_col(csvExecPathname,
                msg="Original, after being exec'ed", skipHeader=True)
            (rowNum2, predictOutput)  = compare_csv_last_col(csvPredictPathname, 
                msg="Predicted", skipHeader=True)

            # no header on source
            if (rowNum1 != rowNum2):
                raise Exception("original rowNum1: %s not same as downloaded predict (w/header) rowNum2: \
                    %s" % (rowNum1, rowNum2))

            wrong = 0
            wrong0 = 0
            wrong1 = 0
            for rowNum,(o,p) in enumerate(zip(originalOutput, predictOutput)):
                o = float(o)
                p = float(p)
                if o!=p:
                    msg = "Comparing original output col vs predicted. row %s differs. \
                        original: %s predicted: %s"  % (rowNum, o, p)
                    if p==0.0 and wrong0==10:
                        print "Not printing any more predicted=0 mismatches"
                    elif p==0.0 and wrong0<10:
                        print msg
                    if p==1.0 and wrong1==10:
                        print "Not printing any more predicted=1 mismatches"
                    elif p==1.0 and wrong1<10:
                        print msg

                    if p==0.0:
                        wrong0 += 1
                    elif p==1.0:
                        wrong1 += 1

                    wrong += 1

            print "wrong0:", wrong0
            print "wrong1:", wrong1
            print "\nTotal wrong:", wrong
            print "Total:", len(originalOutput)
            pctWrong = (100.0 * wrong)/len(originalOutput)
            print "wrong/Total * 100 ", pctWrong
            # I looked at what h2o can do for modelling with binomial and it should get better than 25% error?
            if pctWrong > 10.0:
                raise Exception("pct wrong too high. Expect < 10% error")

        #*************************************************************************
        parseResult = h2i.import_parse(bucket=bucket, path=csvPathname, schema='put', hex_key=hexKey)
        # do the binomial conversion with Exec2, for both training and test (h2o won't work otherwise)
        trainKey = parseResult['destination_key']
        y = 54
        # CLASS=4
        CLASS=1

        if DO_BUG:
            if DO_BUG2:
                # class 4=0, all else 1
                execExpr="A.hex=%s;A.hex[,%s]=(A.hex[,%s]!=%s)" % (trainKey, y+1, y+1, CLASS)
            else:
                # class 4=1, all else 0
                execExpr="A.hex=%s;A.hex[,%s]=(A.hex[,%s]==%s)" % (trainKey, y+1, y+1, CLASS)
            h2e.exec_expr(execExpr=execExpr, timeoutSecs=30)
        else:
            execExpr="A.hex=%s" % trainKey
            h2e.exec_expr(execExpr=execExpr, timeoutSecs=30)
            if DO_BUG2:
                # class 4=0, all else 1
                execExpr="A.hex[,%s]=(A.hex[,%s]!=%s)" % (y+1, y+1, CLASS)
            else:
                # class 4=1, all else 0
                execExpr="A.hex[,%s]=(A.hex[,%s]==%s)" % (y+1, y+1, CLASS)
            h2e.exec_expr(execExpr=execExpr, timeoutSecs=30)

        # does GLM2 take more iterations?
        max_iter = 50
        kwargs = {
            'standardize': 1,
            'classification': 1,
            'response': 'C' + str(y),
            'family': 'binomial',
            'n_folds': 1,

            # FIX! temporary 
            # 'case_mode': '=',
            # 'case_val': 1, # zero should predict to 0, 2-7 should predict to 1
            'max_iter': max_iter,
            'beta_epsilon': 1e-3}

        timeoutSecs = 120

        if 1==1:
            aHack = {'destination_key': 'A.hex'}
        else:
            aHack = {'destination_key': 'covtype.data.hex'}

        if 1==0:
            start = time.time()
            kwargs.update({'alpha': 0, 'lambda': 0}) 
            glm = h2o_cmd.runGLM(parseResult=aHack, timeoutSecs=timeoutSecs, **kwargs)
            print "glm (L2) end on ", csvPathname, 'took', time.time() - start, 'seconds'
            (warnings, coefficients, intercept) = h2o_glm.simpleCheckGLM(self, glm, None, **kwargs)

            modelKey = glm['glm_model']['_selfKey']
            predict_and_compare_csvs(model_key=modelKey)

            kwargs.update({'alpha': 0.5, 'lambda': 1e-5})
            start = time.time()
            glm = h2o_cmd.runGLM(parseResult=aHack, timeoutSecs=timeoutSecs, **kwargs)
            print "glm (Elastic) end on ", csvPathname, 'took', time.time() - start, 'seconds'
            (warnings, coefficients, intercept) = h2o_glm.simpleCheckGLM(self, glm, None, **kwargs)
            modelKey = glm['glm_model']['_selfKey']
            predict_and_compare_csvs(model_key=modelKey)

        kwargs.update({'alpha': 0.5, 'lambda': 1e-5})
        start = time.time()
        glm = h2o_cmd.runGLM(parseResult=aHack, timeoutSecs=timeoutSecs, **kwargs)
        print "glm (L1) end on ", csvPathname, 'took', time.time() - start, 'seconds'
        # we get the non-normalized coefficients
        (warnings, coefficients, intercept) = h2o_glm.simpleCheckGLM(self, glm, None, **kwargs)

        avg_err = glm['glm_model']['submodels'][0]['validation']['avg_err']
        auc = glm['glm_model']['submodels'][0]['validation']['auc']
        best_threshold = glm['glm_model']['submodels'][0]['validation']['best_threshold']
        # coefficients is a list.
        C34 = coefficients[34]

        # compare to known values GLM1 got for class 1 case, with these parameters
        aucExpected = 0.8428
        self.assertAlmostEqual(auc, aucExpected, delta=0.001, msg='auc %s is too different from %s' % (auc, aucExpected))

        interceptExpected = -16.603
        print "intercept pct delta:", 100 * (abs(intercept) - abs(interceptExpected))/abs(interceptExpected)
        self.assertAlmostEqual(intercept, interceptExpected, delta=0.01, msg='intercept %s is too different from %s' % (intercept, interceptExpected))

        avg_errExpected = 0.2463
        self.assertAlmostEqual(avg_err, avg_errExpected, delta=0.01*avg_errExpected, msg='avg_err %s is too different from %s' % (avg_err, avg_errExpected))

        C34expected = 3.541
        print "C34 pct delta:", "%0.2f" % 100 * (abs(C34) - abs(C34expected))/abs(C34expected)
        self.assertAlmostEqual(C34, C34expected, delta=0.001*C34expected, msg='coefficient 34 %s is too different from %s' % (C34, C34expected))
        
        self.assertAlmostEqual(best_threshold, 0.35, delta=0.01*best_threshold, msg='best_threshold %s is too different from %s' % (best_threshold, 0.35))

        modelKey = glm['glm_model']['_selfKey']
        predict_and_compare_csvs(model_key=modelKey)

if __name__ == '__main__':
    h2o.unit_main()
