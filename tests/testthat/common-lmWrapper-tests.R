context('Testing LMLike construction')
test_that('Can construct LMLike', {
    expect_is(obj, 'LMlike')
})

obj <- fit(obj, response=t(assay(fd))[,2])
test_that('Can fit', {
    expect_is(coef(obj, 'C'), 'numeric')
    expect_is(coef(obj, 'D'), 'numeric')    
})

test_that('Handle 0% expression', {
    obj2 <- fit(obj, rep(0, ncol(fd)))
    expect_false(any(obj2@fitted))
})

test_that('Handle Singular Designs', {
    expect_warning(obj2 <- update(obj, ~ . + Stim.Condition*Population), 'estimible')
    obj2 <- fit(obj2)
    expect_false(any(is.na(vcov(obj2, 'C'))))
    expect_false(any(is.na(vcov(obj2, 'D'))))
    expect_false(any(is.na(coef(obj2, which='C', singular=FALSE))))
    expect_false(any(is.na(coef(obj2, which='D', singular=FALSE))))
})

test_that('Handle 100% expression', {
    hushWarning(obj2 <- fit(obj, rnorm(ncol(fd))+20), 'glm.fit')
    expect_is(coef(obj2, 'C'), 'numeric')
    if(obj2@fitted['D']){
        expect_lt(obj2@fitD$df.residual, 1)
    }
})

## Not sure what the best way to handle this is...lmer just drops NAs, while glm.fit throws an ugly error
## test_that('Handle NA', {
##     resp <- obj@response
##     resp[1] <- NA
##     browser()
##     expect_error(obj2 <- fit(obj, resp), 'NA')
## })

test_that('Handle expressions in formulae', {
    obj2 <- update(obj, (~ . +cut(Chip.Number, 2)))
    obj2 <- fit(obj2)
    expect_is(obj2, 'LMlike')
})

context('Testing fit summaries')

test_that('log likelihood is increasing in model complexity', {
    l1 <- logLik(obj)
    obj2 <- update(obj, ~ . -Stim.Condition)
    obj2 <- fit(obj2)
    l0 <- logLik(obj2)
    expect_true(all(l0<=l1))
})

test_that('log likelihood agrees with individual model objects',{
    expect_equivalent(as.numeric((logLik(objC))), logLik(obj)['C'])
    expect_equivalent(as.numeric(logLik(objD)), logLik(obj)['D'])

})

test_that('log likelihood is invariant to scaling', {
    l1 <- logLik(obj)
    fit(obj, response=obj@response*10)
    l2 <- logLik(obj)
    expect_equal(l1, l2)

})

test_that('Can handle no residual DOF', {
    resp <- obj@response
    resp <- rep(0, length(resp))
    d <- obj@design
    resp[which(d$Stim.Condition=='Unstim')[1]] <- rnorm(1)+10
    resp[which(d$Stim.Condition!='Unstim')[1]] <- rnorm(1)+20
   tt <- try({
    obj2 <- fit(obj, resp)              #throwing an error here is also acceptable
    lrt <- lrTest(obj2, 'Stim.Condition')
})
    if(!is(tt, 'try-error')){
        expect_false(obj2@fitted['C'])
        expect_equal(lrt['cont', 'lambda'], 0)
    }
    
})

test_that('Can get variance/cov', {
    expect_equivalent(vcov(obj, 'C'), as.matrix(vcov(objC)))
    expect_equivalent(vcov(obj, 'D'), as.matrix(vcov(objD)))
})


suppressWarnings(obj2 <- fit(update(obj, ~ .+Stim.Condition*Population)))

context('Post hoc testing')
test_that('LRT For Glm', {
 atest <- lrTest(obj, 'Stim.Condition')
 expect_is(atest, 'matrix')
 expect_true(all(atest[,'lambda']>0))

 hushWarning(btest <- lrTest(obj2, 'Stim.Condition'), fixed('Coefficients PopulationCD154+VbetaResponsive:Stim.ConditionUnstim, PopulationCD154+VbetaUnresponsive:Stim.ConditionUnstim, PopulationCD154-VbetaResponsive:Stim.ConditionUnstim, PopulationCD154-VbetaUnresponsive:Stim.ConditionUnstim are never estimible and will be dropped.'))
 expect_true(all(btest[,'df']==0))
 btest <- lrTest(obj2, 'Stim.Condition:Population')
 expect_equal(btest['cont','df'],1)
 
})

    atest <- lrTest(obj, 'Stim.Condition')
context('LRT Contrasts')
test_that('Contrast Hypothesis Work', {
    coefh <- hushWarning(generateHypothesis(Hypothesis('Stim.ConditionUnstim'), names(coef(obj, 'D'))), 'Some levels contain symbols.')
    hushWarning(btest <- lrTest(obj, coefh), 'consider rescaling')
    expect_equivalent(atest,btest)
    expect_warning(coefh <- generateHypothesis(Hypothesis('`Stim.ConditionUnstim:PopulationVbetaResponsive`'), names(coef(obj2, 'D'))), 'backticks')
    hushWarning(btest <- lrTest(obj2, coefh), 'consider rescaling')
    ctest <- lrTest(obj2, 'Stim.Condition:Population')
    ## prior, hence results changes slightly due to bayesglm magic scaling...
    err <- if(inherits(obj2, 'BayesGLMlike')) .01 else 1e-7
    expect_true(all.equal(btest,ctest, tolerance=err, check.attributes=FALSE))
    
    suppressWarnings(coefh <- generateHypothesis(Hypothesis(c('`Stim.ConditionUnstim:PopulationVbetaResponsive`-`(Intercept)`', 'PopulationVbetaResponsive')), names(coef(obj2, 'D'))))                          
    dtest <- lrTest(obj2, coefh)
    expect_is(dtest, 'matrix')
    expect_equivalent(dtest[1:2, 'df'], c(2,2))
})

## library(car)
## test_that('LRT agree with manual', {
##     d <- Anova(objD, test='LR')[1,'LR Chisq']
##     cont <- car:::Anova.glm(objC, test='LR', error.estimate='deviance')[1,'LR Chisq']
##     d0 <- objC$null.deviance
##     d1 <- objC$deviance
##     s0 <- sqrt(d0/objC$df.null)
##     s1 <- sqrt(d1/objC$df.resid)
##     lrt <- lrTest(obj, 'Stim.Condition')
##     ## for some reason we're off by ~1% here...
##     expect_equivalent(lrt['hurdle', 'lambda'], sum(ifelse(lrt[1:2, 'df']>0,c(cont,d),c(0,0))))
## })

test_that('Wald For Glm', {
    btest <- waldTest(obj, as.matrix(c(0, 1)))
    hypo <- generateHypothesis(CoefficientHypothesis('Stim.ConditionUnstim'), colnames(model.matrix(obj)))
 atest <- waldTest(obj, hypo)
 expect_is(btest, 'matrix')
 expect_equivalent(btest, atest)
 
     if(require(car)){
          chic <- lht(obj@fitC, test='Chisq', 'Stim.ConditionUnstim', vcov.=vcov(obj, 'C'))[2,'Chisq']
          chid <- lht(obj@fitD, 'Stim.ConditionUnstim', vcov.=vcov(obj, 'D'))[2,'Chisq']
         expect_equal(btest['cont', 'lambda'], chic)
         expect_equal(btest['disc', 'lambda'], chid)
     }
})


test_that('Residuals', {
    expect_equivalent(as.numeric(residuals(obj, which='C', type='response')), residuals(objC))
    expect_equivalent(as.numeric(residuals(obj, which='D', type='response')), residuals(objD, type='response'))
})
