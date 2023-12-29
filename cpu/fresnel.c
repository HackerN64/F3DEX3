/* Bonus: To convert Fresnel lo and hi (values for where the Fresnel fade begins
/* and ends, normally between 0.0 and 1.0) to scale and offset for SPFresnel */
void FresnelParams(s16* scale, s16* offset, float lo, float hi){
    s32 dotMin = (s32)(lo * 0x7FFF);
    s32 dotMax = (s32)(hi * 0x7FFF);
    if(dotMax == dotMin) ++dotMax;
    s32 scale32 = 0x3F8000 / (dotMax - dotMin);
    s32 offset32 = -(0x7F * dotMin) / (dotMax - dotMin);
    *scale = (s16)MAX(MIN(scale32, 0x7FFF), -0x8000);
    *offset = (s16)MAX(MIN(offset32, 0x7FFF), -0x8000);
}
